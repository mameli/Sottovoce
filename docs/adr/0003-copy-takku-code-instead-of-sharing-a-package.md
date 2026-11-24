# Copy Takku's transcription code instead of sharing a package

The audio import, speech detection and transcription code comes from Takku, where it lives inside the app target and depends on Takku's settings. Sottovoce copies and adapts it rather than extracting a Swift package both apps depend on: extracting would slow Takku down, and the needs already differ (Sottovoce keeps per-word timings, Takku throws them away). The duplication is deliberate; merge only if the two copies keep changing in the same way.
