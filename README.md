# emacs-rubocop-fast

The official Rubocop emacs library (https://github.com/bbatsov/rubocop-emacs) is slow at autocorrection because it updates the the current buffer's file on disk, which triggers `revert-buffer` eventually. It also makes an annoying split window with all of the output.

This library is based on the prettier-js emacs library at https://github.com/prettier/prettier-emacs, which does a diff/patch into the buffer, and is much smoother in my experience.

`flycheck` already supports a nice checker for `rubocop`, to inspect errors and warnings
