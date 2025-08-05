# Changes

## Next

- Add `--interactive` option for interactive screenshot selection using `screencapture -i`.
- Change default filename to `YYYY-MM-DD Screenshot.png`.

## 1.1.0

- Create screenshot at perceived size, not retina size. Provide `--no-resize` to disable this.
- Add `--quiet` (& `-q`) option to suppress output messages.

## 1.0.0

- Create screenshot of active window using screencapture.
- Write to file in ~/Downloads by default, use --file to set filename.
- Write to clipboard with `--clipboard`.
