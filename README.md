# jakski.github.io

Static blog generation tool.

## Dependencies

Debian packages:

- libmd4c-dev
- libmd4c-html0-dev
- libjansson-dev
- meson
- ninja-build
- build-essential

## Building and running

```
$ meson setup build
$ meson compile -C build
$ ./build/jakski-blog cfg.json
```
