import { networkInterfaces } from 'os';

export function getLocalIP(interfaces = networkInterfaces()): string {
  for (const addresses of Object.values(interfaces)) {
    for (const address of addresses ?? []) {
      if (address.family === 'IPv4' && !address.internal) return address.address;
    }
  }
  return '0.0.0.0';
}
