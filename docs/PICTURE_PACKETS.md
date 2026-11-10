# Import a prepared picture packet

The caregiver editor can load a small JSON picture packet from Files. It is a
picture-selection bridge, not a backup format. Confirming import replaces the
board with the packet's cells; the previous generation is retained internally.
Recordings, navigation and other full-board data are not carried by this format.

```json
{
  "version": 1,
  "selections": [
    {
      "card": {"id": "example-cup", "label": "Cup", "spokenText": "A cup, please", "slot": 0},
      "asset": {
        "data": "data:image/png;base64,<base64 image bytes>",
        "source": "Caregiver photo",
        "author": "Photo owner",
        "license": "Used with permission",
        "modifications": "None"
      }
    }
  ]
}
```

Replace the placeholder with actual PNG or JPEG bytes encoded as a data URL.
All shown asset fields are required; `license_url` is optional. `spokenText` is
optional and defaults to the label. Slots are zero-based row-major indexes from
0 to 14 on a 3 by 5 grid. IDs and occupied slots must be unique. One to fifteen
selections are accepted, within the 20 MiB packet limit. Labels must be nonblank.

SVG and remote image URLs are not accepted. Images are decoded and normalized
before saving; unsupported, excessively large or unreadable input is rejected.
Keep appropriate permission and attribution for the media you supply.
