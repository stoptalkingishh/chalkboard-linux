# ScratchJr web launcher research

Last checked: 2026-09-08

## Decision

Do not install a ScratchJr browser launcher. No candidate met both the trust and
desktop-browser support requirements. The official site is maintained and uses
HTTPS, but it is an informational and download site rather than a web edition of
ScratchJr. Browser ports that do run are explicitly unofficial community work.

This distinction matters for a child-facing launcher: a working page is not
enough to establish who operates it, who will maintain it, or whether the
ScratchJr publishers support children using it.

## Evidence

### Official website

- [`scratchfoundation/scratchjr-website`](https://github.com/scratchfoundation/scratchjr-website)
  is owned by the Scratch Foundation GitHub organization, is not archived, uses
  the BSD-3-Clause license, and received updates in August 2026. This establishes
  provenance and current maintenance for the website, not for a web editor.
- The site's [home-page source](https://github.com/scratchfoundation/scratchjr-website/blob/18700d3a5615355ac7bf6098e154bb2dccf56712/src/views/index/index.jsx)
  says ScratchJr is available as an app and links only to the Apple, Google Play,
  and Amazon stores.
- The June 2026 [device FAQ source](https://github.com/scratchfoundation/scratchjr-website/blob/18700d3a5615355ac7bf6098e154bb2dccf56712/src/views/about/faq.jsx)
  describes iPad and Android support. Chromebook, Apple silicon Mac, and Windows
  support use store apps in platform containers; it does not claim ordinary
  desktop-browser support.
- The published [route list](https://github.com/scratchfoundation/scratchjr-website/blob/18700d3a5615355ac7bf6098e154bb2dccf56712/src/routes.json)
  contains informational, teaching, research, and support pages, but no editor or
  play route.
- `https://www.scratchjr.org/` completed TLS validation and rendered the
  informational home page in headless Chromium 153 at 1366 by 768. A direct
  request and Chromium navigation to `https://www.scratchjr.org/play` returned
  an Amazon S3 `NoSuchKey` 404. Launching the home page as an app would therefore
  misrepresent a marketing/download page as playable ScratchJr.

### Official application source

- [`scratchfoundation/scratchjr`](https://github.com/scratchfoundation/scratchjr)
  is the official BSD-3-Clause application source, but GitHub marks it archived.
  Its latest `develop` commit is from April 2022.
- Its [README](https://github.com/scratchfoundation/scratchjr/blob/ff15b0f5f0eb404c87a7554e43e18992f50bd32d/README.md)
  lists iOS and Android as released and a pure-web version as future work. An
  open-source license permits reuse; it does not make a third-party deployment
  official or currently maintained.

### Community browser and desktop ports

- [`patdx/scratchjr`](https://github.com/patdx/scratchjr/tree/bf29c3fbc6882f3faedf1dede6afc60ad863da89) is BSD-3-Clause code
  with recent August 2026 activity. Its README and package metadata both call it
  an **unofficial community port**, and its hosted instance is on the
  maintainer's `pmil.me` domain rather than a ScratchJr publisher's domain.
- `https://scratchjr.pmil.me/` passed TLS validation, returned restrictive
  browser security headers, and rendered the ScratchJr environment-selection
  screen in headless Chromium 153 at 1366 by 768. This confirms that it is a real
  browser candidate, but not that project creation, persistence, media features,
  or long-term operations are reliable. More importantly, its own provenance
  disclaimer fails the publisher-trust requirement, so children must not be
  directed to it by this project.
- [`jfo8000/ScratchJr-Desktop`](https://github.com/jfo8000/ScratchJr-Desktop/tree/919482d724904a560d6c77dab06240341584c502)
  is also explicitly an independent community port. Its latest commit is from
  November 2020, its page offers unsigned Mac and Windows installers rather than
  browser play, and at review time its issue tracker shows 98 open issues (120
  open items when pull requests are included in the count). It is neither a
  maintained web service nor a Fedora package candidate.
- Scratch 3 at `scratch.mit.edu` is a separate product for a different age range
  and is not a substitute for ScratchJr.

## Acceptance criteria

A future opt-in Vivaldi app launcher may be proposed only when every item below
has reproducible evidence:

1. The hosted editor is operated by, or explicitly endorsed as a supported web
   edition by, the Scratch Foundation or another identifiable ScratchJr
   publisher. A community disclaimer or copied trademark is not endorsement.
2. The exact editor URL is linked from current publisher documentation and has
   an identified maintenance and security-reporting path.
3. Source and asset licenses are published and compatible with the deployment;
   trademark terms do not make the launcher misleading.
4. The direct editor URL uses valid HTTPS, loads without certificate bypasses or
   active mixed content, and does not redirect to an unrelated Scratch product,
   app-store page, or informational page.
5. On the supported Fedora and Vivaldi versions, a graphical test can create a
   project, add and run blocks with mouse or touch, save it, close the browser,
   and load it again. Expected camera, microphone, import, and export behavior is
   documented and tested.
6. The operator's privacy practices and the editor's external requests are
   reviewed for child use, including analytics and persistence. A parent must
   explicitly opt in before the launcher is placed on the child panel.
7. Deployment verification checks both the installed desktop entry and the
   effective panel item, while the runbook identifies a parent-owned removal and
   re-verification procedure.

Until all criteria pass, ScratchJr remains documentation-only and executable
references under `config/` or `scripts/` are intentionally rejected by the
static test suite.
