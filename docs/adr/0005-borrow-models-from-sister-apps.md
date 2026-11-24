# Borrow models already downloaded by the Sister Apps

Before downloading a model, Sottovoce looks for it in its own folder, then in Takku's and Dimmela's (`~/Library/Application Support/Takku/Models`, `.../Dimmela/Models`), and uses one only when that app's fully-downloaded marker (`.takku-downloaded`, `.dimmela-downloaded`) is next to it. It only reads those folders, never writes or deletes there; if nothing is found, or a borrowed model fails to load (a different FluidAudio version, say), it downloads into its own folder. This saves a download of hundreds of megabytes on a Mac that already runs a Sister App, without changing Takku or Dimmela.

## Consequences

- It depends on the Sister Apps' folder layout and marker names, which they may change; a miss only costs a download.
- A model deleted in a Sister App is downloaded again by Sottovoce the next time it is needed.
- Sharing is one way: the Sister Apps do not look in Sottovoce's folder. A model folder shared by all three apps was left for later, since it needs changes to Takku and Dimmela.
