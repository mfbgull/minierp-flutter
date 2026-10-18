jest.mock('better-sqlite3', () => {
  const Constructor = jest.requireActual<typeof import('better-sqlite3')>('better-sqlite3');
  const { protectDatabaseConstructor } = jest.requireActual<typeof import('./liveDbGuard')>('./liveDbGuard');
  return protectDatabaseConstructor(Constructor);
});
