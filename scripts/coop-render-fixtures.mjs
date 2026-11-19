// Record production room replies quickly, then let offscreen WebGL consume them at its own pace.
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';

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
      const notice = await waitFor(() => messages.get('notice'), 'repair acknowledgement');
      assert.ok(notice.ok && notice.site === 'repair', 'The authoritative room did not repair the lamp');
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
  await context.route(url => url.pathname === '/coop/index.js', async route => {
    const response = await route.fetch();
    const runtime = await response.text();
    const clock = /var _emscripten_get_now\s*=\s*\(\)\s*=>\s*performance\.now\(\)/;
    if (!response.ok() || !clock.test(runtime)) {
      await route.fulfill({status: 502, body: 'Software capture could not find the pinned Godot runtime clock'});
      return;
    }
    await route.fulfill({contentType: 'text/javascript',
      body: runtime.replace(clock, 'var _emscripten_get_now=()=>window.coopFixtureClock()')});
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
