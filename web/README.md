# LEXIS marketing site

Static files for the LEXIS marketing page, privacy policy, and `app-ads.txt`.
This folder is **not** part of the app build (the Xcode target only includes
`LEXIS/`) — it's meant to be deployed to a website you control.

## Files
- `index.html` — marketing landing page (use its URL as the App Store **Marketing URL**).
- `privacy.html` — privacy policy (use its URL as the App Store **Privacy Policy URL**).
- `app-ads.txt` — authorized-sellers file AdMob crawls. **Edit it** to insert your AdMob publisher ID.

## Deploy (pick one)

`app-ads.txt` **must be served from the ROOT of the domain** you list as the
app's Marketing URL — e.g. `https://yourdomain.com/app-ads.txt`. A project
subpath like `user.github.io/lexis/app-ads.txt` will **not** be found. So the
host has to serve this folder as the site root:

- **Netlify / Cloudflare Pages / Vercel (fastest, free):** drag-and-drop this
  `web/` folder (or point the host at it). You get a root domain like
  `lexis.netlify.app` that serves `/app-ads.txt`, `/`, and `/privacy.html`.
- **GitHub Pages user site:** put these files in a repo named
  `<username>.github.io` so they serve at `https://<username>.github.io/`.
- **Your own domain:** point it at any of the above. Most professional; ~$10/yr.

## Before you ship
1. In `app-ads.txt`, replace `pub-0000000000000000` with your AdMob publisher ID.
2. In `index.html` + `privacy.html`, replace `hello@lexisgame.app` with a real
   support inbox, and set the App Store download link once the app is live.
3. In App Store Connect, set **Marketing URL** = your deployed `index.html`,
   **Privacy Policy URL** = your deployed `privacy.html`, and make sure the
   marketing domain matches where `app-ads.txt` is hosted.
