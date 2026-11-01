# timetable-pdf

Small Sinatra service that renders printable PDFs of Lviv public transport stop
timetables. It fetches pages from
[timetable-offline](https://offline.lad.lviv.ua) and converts them with
`wkhtmltopdf`.

## Endpoints

| Route | Output |
| --- | --- |
| `GET /:code.pdf` | Stop timetable, 460×310 mm page. Downloads as `<code>.pdf`. |
| `GET /:code/schema.pdf` | Network schema poster for the stop, fitted to A1 height (691.4×594 mm). Downloads as `<code>-schema.pdf`. |
| `GET /:code/panel.pdf` | The plate inside the shelter, 4000×300 mm; `?length=4` gives the 3000 mm plate for 4 m shelters. The page is sized from the SVG's own viewBox, so the plate length is decided in timetable-offline; it is 0.5 mm short of the viewBox's height, since wkhtmltopdf paints about a point less than the page it rounds up to, and this keeps the plate edge to edge on one page. Downloads as `<code>-panel.pdf`. |

`:code` is the stop code printed on the stop sign (e.g. `707`); it must match
`[A-Za-z0-9_-]{1,32}`, anything else is a 404.

### Route overrides

The timetable and schema endpoints accept optional query parameters that are
passed through to timetable-offline unchanged (the panel takes only `length`):

- `only` — draw only these routes
- `add` — add routes to the stop's own list
- `remove` — drop routes from the stop's own list

Each value is a comma-separated list of route names (Latin or Cyrillic
alphanumerics, up to 16 characters each), e.g. `?only=Т30,А47`. A malformed
value returns 400.

```sh
curl -o 707.pdf 'http://localhost:4567/707.pdf?remove=А03'
curl -o 707-schema.pdf 'http://localhost:4567/707/schema.pdf'
curl -o 707-panel.pdf 'http://localhost:4567/707/panel.pdf?length=4'
```

### Responses

- `200` — the PDF, sent with `Cache-Control: no-store` so Cloudflare does not
  hold stale timetables at the edge.
- `400` — bad override or `length` parameter, or upstream rejected the stop
  (schema and panel).
- `404` — invalid stop code, or upstream has no such stop (schema and panel).
- `502` — upstream fetch or PDF generation failed.

Generated files are cached in `/tmp`, keyed by stop code, kind and a hash of
the upstream URL (so different override sets never collide).

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `OFFLINE_URL` | `https://offline.lad.lviv.ua` | Base URL of timetable-offline. |

The server (Thin) listens on `0.0.0.0:4567`.

## Running locally

The app needs the specific static `wkhtmltopdf` build pinned in the
`Dockerfile`, so Docker is the easiest way to run it. That binary is x86-64
only, so the image is always built for `linux/amd64` (emulated on Apple
Silicon):

```sh
docker buildx build --platform linux/amd64 --load -t timetable-pdf .
docker run --rm --platform linux/amd64 -p 4567:4567 timetable-pdf
```

Without Docker (requires Ruby 3.1+ and `wkhtmltopdf` on `PATH`):

```sh
bundle install
./entrypoint.sh
```

To regenerate `Gemfile.lock` inside a matching Ruby container:

```sh
./build-gemfilelock.sh
```

## Image

A two-stage build keeps the image small (about 53 MB, down from 300 MB):

- the build stage, `ruby:3.1-alpine3.18`, compiles the native gems
  (`eventmachine` for Thin), then drops gem sources, caches, Ruby's headers,
  static lib and dev-only bundled gems;
- the runtime stage is bare `alpine:3.18` with Ruby copied over, plus only the
  libraries Ruby and `wkhtmltopdf` link against (`ldd` is the list).

Alpine stays on 3.18 because the 2019 `wkhtmltopdf` build needs OpenSSL 1.1
(`openssl1.1-compat`), which later releases no longer package.

Every drawing from timetable-offline embeds its own fonts as `@font-face`, so
the PDFs carry only Myriad Pro. The image ships just DejaVu Sans as the
fontconfig fallback.

## Build and deploy

Deployed to Google Cloud Run (project `timetable-252615`, region
`europe-north1`).

```sh
make build    # build linux/amd64 image and push to gcr.io/timetable-252615/timetable-pdf
make deploy   # build, then roll the image out to Cloud Run and print URL + revision
```

`PROJECT`, `IMAGE`, `SERVICE` and `REGION` can be overridden on the `make`
command line for `deploy`; `build.sh` always pushes to the image above. It disables buildx provenance/SBOM attestations and
forces Docker media types, because Cloud Run rejects OCI image indexes.

`deploy` keeps the service's existing environment variables and settings.
