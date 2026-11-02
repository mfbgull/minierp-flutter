# server/client

`dist/` is a Flutter **web** build of the desktop client. `server/src/app.ts`
serves it as static files in production. It was tracked in git by mistake and
removed on 2026-11-02; it is now gitignored.

To regenerate:

```bash
# from the repository root
flutter build web
rm -rf server/client/dist
cp -r build/web server/client/dist
```

A local copy on disk is required only when running the server in production
mode or serving the web client. Development against the desktop client does
not need it.
