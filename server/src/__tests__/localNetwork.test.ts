import type { NetworkInterfaceInfo } from 'os';
import { getLocalIP } from '../utils/localNetwork';

const ipv4 = (address: string, internal = false): NetworkInterfaceInfo => ({
  address, internal, family: 'IPv4', netmask: '255.255.255.0',
  mac: '00:00:00:00:00:00', cidr: null,
});

it('selects the first external IPv4 in adapter enumeration order', () => {
  expect(getLocalIP({
    missing: undefined,
    loopback: [ipv4('127.0.0.1', true)],
    first: [{ ...ipv4('::1'), family: 'IPv6', scopeid: 0 }, ipv4('192.0.2.1')],
    second: [ipv4('192.0.2.2')],
  })).toBe('192.0.2.1');
});

it('falls back when no external IPv4 interface is available', () => {
  expect(getLocalIP({})).toBe('0.0.0.0');
  expect(getLocalIP({ loopback: [ipv4('127.0.0.1', true)], missing: undefined })).toBe('0.0.0.0');
});
