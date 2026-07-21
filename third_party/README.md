# Third-party dependencies

Only the pinned FFTW 3.3.10 source archive is retained for offline ZQ500 builds:

- `fftw/dist/fftw-3.3.10.tar.gz`
- SHA256: `56c932549852cddcfafdab3820b0200c7742675be92179e59e6215b340e26467`

Run `scripts/build/install_fftw.sh` to verify, extract, build, and install it under
`third_party/fftw/install`. The extracted source, build tree, install tree, and Python wheel
cache are generated dependencies and are excluded from delivery.
