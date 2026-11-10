# Privacy

Talkboard has no application account, analytics SDK or application backend. It
stores board data and copied media in its local app container. Speech and recorded
output use device APIs and local files; the app makes no direct network requests.

System services have their own behavior. Photos may fetch an iCloud item when
selected; voice downloads and operating-system device backups are controlled by
the system and user settings. Talkboard does not promise that OS-managed backups
or photo-library contents stay off cloud services.

The photo picker grants access to the selected items without requesting full
photo-library access. Imported photos are re-encoded to an upright JPEG with a
maximum 1024-pixel long edge; original image metadata is not copied into the JPEG.
Source and license information explicitly attached to board assets is retained.

Caregiver authentication protects editing. It does not encrypt the board or
replace device security settings. Guided Access is configured at the system level.

Deleting the app can delete its local board. In-app export/restore is not yet
implemented. The internal previous generation helps recover some failed saves;
it is not an independently portable backup.

Do not submit personal boards, photos, recordings, device identifiers, signing
material or unredacted device logs in issues or pull requests. Use invented data
and synthetic images when reporting a problem.
