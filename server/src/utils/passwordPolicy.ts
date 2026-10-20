export const MIN_PASSWORD_CHARACTERS = 12;
export const MAX_PASSWORD_BYTES = 72;

export function passwordPolicyError(password: unknown): string | null {
  if (typeof password !== 'string') return 'Password must be a string';
  if ([...password].length < MIN_PASSWORD_CHARACTERS) {
    return `Password must be at least ${MIN_PASSWORD_CHARACTERS} characters long`;
  }
  if (Buffer.byteLength(password, 'utf8') > MAX_PASSWORD_BYTES) {
    return `Password must not exceed ${MAX_PASSWORD_BYTES} UTF-8 bytes; use fewer characters`;
  }
  return null;
}
