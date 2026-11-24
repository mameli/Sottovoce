# Borrow models already downloaded by the Sister Apps

Before downloading a model, Sottovoce looks for it in its own folder, then in Takku's and Dimmela's (`~/Library/Application Support/Takku/Models`, `.../Dimmela/Models`), and uses one only when that app's fully-downloaded marker (`.takku-downloaded`, `.dimmela-downloaded`) is next to it. It only reads those folders, never writes or deletes there; if nothing is found, or a borrowed model fails to load (a different FluidAudio version, say), it downloads into its own folder, with its own marker (`.sottovoce-downloaded`). Takku and Dimmela adopt the same rule, so a model downloaded by any of the three apps serves all of them.

## Considered Options

- **A model folder shared by the three apps**: rejected, it means moving the models Takku and Dimmela already downloaded and coordinating deletions between apps.

## Consequences

- Each app depends on the others' folder layout and marker names; a miss only costs a download.
- A model deleted in one app is downloaded again by another the next time it needs it.
