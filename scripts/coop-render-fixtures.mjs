// Record production room replies quickly, then let offscreen WebGL consume them at its own pace.
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir, readdir, readFile, symlink, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';

export const divePose = {maxY: -1.02, tolerance: 0.002};

async function waitFor(read, description) {
  const deadline = Date.now() + 9000;
  while (Date.now() < deadline) {
    const value = read();
    if (value) return value;
    await new Promise(done => setTimeout(done, 20));
  }
  throw Error('Could not record room fixture: ' + description);
}

function pinClock(snapshot, clock) {
  const copy = structuredClone(snapshot);
  const offset = clock - snapshot.elapsed;
  copy.elapsed = clock;
  copy.groveElapsed += offset;
  for (const actor of [copy.dog, copy.crocodile]) {
    if (typeof actor?.clipAt === 'number') actor.clipAt += offset;
  }
  return copy;
}

export async function recordSoftwareRoom(origin, room, token, scene, warmup) {
  const socket = new WebSocket(origin.replace(/^http/, 'ws') + '/room');
  const messages = new Map();
  const send = data => socket.send(JSON.stringify(data));
  socket.addEventListener('message', ({data}) => {
    const message = JSON.parse(data.toString());
    messages.set(message.t, message);
  });
  try {
    await waitFor(() => socket.readyState === WebSocket.OPEN, 'socket opening');
    send({t:'join', room, token, session:randomBytes(12).toString('hex')});
    const welcome = await waitFor(() => messages.get('welcome'), 'welcome');
    const initial = await waitFor(() => messages.get('snapshot'), 'initial snapshot');
    const clock = scene.clock + warmup;
    const fixture = {welcome, initial: pinClock(initial, clock), roomClock: clock};
    if (scene.transition === 'repair') {
      send({t:'act', site:'repair'});
      const notice = await waitFor(() => {
        const reply = messages.get('notice');
        return reply?.site === 'repair' && reply;
      }, 'repair acknowledgement');
      assert.ok(notice.ok, 'The room rejected the repair: ' + notice.text);
      const repaired = await waitFor(() => messages.get('snapshot')?.quest?.repaired && messages.get('snapshot'), 'repaired snapshot');
      fixture.repair = [pinClock(repaired, clock), notice];
    }
    if (scene.diving) {
      const move = lift => send({t:'motion', x:0, z:0, yaw:scene.yaw, lift});
      move(-1);
      const timer = setInterval(() => move(-1), 65);
      let previous;
      let settled = 0;
      try {
        const submerged = await waitFor(() => {
          const current = messages.get('snapshot');
          if (current === previous) return false;
          const player = current.players[welcome.id];
          const prior = previous?.players[welcome.id];
          settled = player.swimming && player.y < divePose.maxY && prior?.swimming &&
            Math.abs(player.y - prior.y) <= divePose.tolerance ? settled + 1 : 0;
          previous = current;
          return settled >= 2 && current;
        }, 'settled lakebed snapshot');
        fixture.submerged = pinClock(submerged, clock);
      } finally {
        clearInterval(timer);
        move(0);
      }
    }
    return fixture;
  } finally {
    socket.close();
  }
}

// Runs in the browser before Godot starts compiling shaders on the CPU. Use the
// release's own fetcher and its real timeout for each file. Godot still parses
// and installs the exact downloaded model when the chunk enters its streaming range.
async function warmZoneDownloads(files) {
  const join = window.CooperJoin;
  if (!join.fetchZone) return; // Older releases stream through Godot itself.
  const fetchZone = join.fetchZone.bind(join);
  const tickets = new Map();
  await Promise.all(files.map(async file => {
    const url = new URL(file, join.zoneBase).href;
    const ticket = fetchZone(url);
    while (!ticket.done) await new Promise(done => setTimeout(done, 25));
    if (ticket.error || !ticket.bytes?.byteLength) throw Error('Cannot load ' + url + ': ' + ticket.error);
    tickets.set(url, ticket);
  }));
  join.fetchZone = url => {
    const ticket = tickets.get(url);
    if (!ticket) return fetchZone(url);
    tickets.delete(url);
    return ticket;
  };
}

export async function prepareSoftwareSite(build, site) {
  await mkdir(site);
  const runtime = await readFile(resolve(build, 'index.js'), 'utf8');
  const clock = /var _emscripten_get_now\s*=\s*\(\)\s*=>\s*performance\.now\(\)/;
  assert.ok(clock.test(runtime), 'Software capture could not find the pinned Godot runtime clock');
  await writeFile(resolve(site, 'index.js'), runtime.replace(clock,
    'var _emscripten_get_now=()=>window.coopFixtureClock()'));
  const html = await readFile(resolve(build, 'index.html'), 'utf8');
  const start = 'await new Engine(config).startGame()';
  assert.ok(html.includes(start), 'Cannot find the game startup in the release HTML');
  const zones = (await readdir(resolve(build, 'zones'))).filter(file => file.endsWith('.glb'));
  assert.ok(zones.length, 'The release has no streamed map chunks');
  await writeFile(resolve(site, 'index.html'), html.replace(start,
    () => `await (${warmZoneDownloads.toString()})(${JSON.stringify(zones)}); ${start}`));
  for (const file of await readdir(build)) {
    if (!['index.js', 'index.js.gz', 'index.html', 'index.html.gz'].includes(file)) {
      await symlink(resolve(build, file), resolve(site, file));
    }
  }
  return site;
}

export async function installSoftwareRoomReplay(context, fixtures) {
  // The rasterizer may take several wall-clock seconds per frame. Advance only
  // the game runtime's monotonic clock with displayed frames. Browser frame
  // measurements continue to receive the unmodified rAF timestamps.
  await context.addInitScript(() => {
    let time = 0;
    let step = 1000 / 60;
    const requestFrame = window.requestAnimationFrame.bind(window);
    function advance() {
      time += step;
      requestFrame(advance);
    }
    window.coopFixtureClock = () => time;
    window.coopFixtureSetStep = frameSeconds => { step = frameSeconds * 1000; };
    requestFrame(advance);
  });
  await context.routeWebSocket(url => url.pathname === '/room', socket => {
    let fixture;
    let current;
    let joinedAt = 0;
    const send = data => socket.send(JSON.stringify(data));
    socket.onMessage(message => {
      const input = JSON.parse(message.toString());
      if (input.t === 'join') {
        fixture = fixtures.get(new URL(socket.url()).host + '/' + input.room);
        assert.ok(fixture, 'No recorded software fixture for ' + input.room);
        current = fixture.initial;
        joinedAt = Date.now();
        send(fixture.welcome);
        send(current);
      } else if (fixture && input.t === 'act' && input.site === 'repair' && fixture.repair) {
        [current] = fixture.repair;
        send(current);
        send(fixture.repair[1]);
      } else if (fixture && input.t === 'motion') {
        if (input.lift < 0 && fixture.submerged) current = fixture.submerged;
        send(fixture.sunrise ? pinClock(current, fixture.roomClock + (Date.now() - joinedAt) / 1000) : current);
      }
    });
  });
}
