import { lookup } from 'node:dns/promises';
import { BlockList, isIP } from 'node:net';
import { networkInterfaces } from 'node:os';

const loopbacks = new BlockList();
loopbacks.addSubnet('127.0.0.0', 8, 'ipv4');
loopbacks.addAddress('::1', 'ipv6');

async function localAddresses(hostname) {
  const host = hostname.replace(/^\[|\]$/g, '');
  const family = isIP(host);
  const addresses = family ? [{ address: host, family }] : await lookup(host, { all: true }).catch(() => []);
  const interfaces = Object.values(networkInterfaces()).flatMap(entries => entries || []);
  const local = new BlockList();
  for (const { address } of interfaces) local.addAddress(address, 'ipv' + isIP(address));
  const isLoopback = ({ address, family }) => loopbacks.check(address, 'ipv' + family);
  if (!addresses.length || !addresses.every(entry => isLoopback(entry) || local.check(entry.address, 'ipv' + entry.family))) return null;
  return { loopback: addresses.every(isLoopback) };
}

async function campHealth(origin) {
  try {
    const response = await fetch(new URL('/health', origin), { redirect: 'error', signal: AbortSignal.timeout(1800) });
    if (!response.ok) return null;
    const health = await response.json();
    return health?.game === 'cooper-camp' && health.ready === true ? health : null;
  } catch {
    return null;
  }
}

function advertisedOrigin(health, fallback) {
  if (!health.advertised) return fallback;
  try {
    const url = new URL(health.advertised);
    if (['http:', 'https:'].includes(url.protocol)) return url.origin;
  } catch {}
  return fallback;
}

export async function resolveNativeJoin(link) {
  const local = new URL('http://localhost:' + (process.env.COOP_PORT || 4184) + '/coop/');
  const invite = new URL(link || local.href, local);
  if (!['http:', 'https:'].includes(invite.protocol)) throw Error('请输入网页邀请链接。');
  const room = invite.searchParams.get('room') || 'pine';
  let transport = new URL(invite.origin);
  let publicOrigin = invite.origin;

  // Keep HTTPS hostnames for certificate validation. A local HTTP invite can use
  // loopback only when a ready camp is listening there on the invitation's port.
  if (invite.protocol === 'http:') {
    const self = link ? await localAddresses(invite.hostname) : { loopback: true };
    if (self) {
      const loopback = new URL(invite.origin);
      loopback.hostname = '127.0.0.1';
      const health = await campHealth(loopback);
      if (!link && !health) throw Error('请先运行 npm run coop。');
      if (health && (self.loopback || health.lan === true)) {
        transport = loopback;
        if (self.loopback) publicOrigin = advertisedOrigin(health, publicOrigin);
      }
    }
  }

  const websocket = new URL('/room', transport);
  websocket.protocol = transport.protocol === 'https:' ? 'wss:' : 'ws:';
  return {
    room,
    websocketUrl: websocket.href,
    zoneBase: new URL('/coop/zones/', transport).href,
    inviteUrl: publicOrigin + '/coop/?room=' + encodeURIComponent(room),
  };
}

export function nativeJoinArgs({ room, websocketUrl, zoneBase, inviteUrl }) {
  return ['--room=' + room, '--url=' + websocketUrl, '--zone-base=' + zoneBase, '--invite-url=' + inviteUrl];
}
