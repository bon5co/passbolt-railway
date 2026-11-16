# Passbolt CE for Railway

Wrapper over the upstream `passbolt/passbolt` non-root image (5.18.0-1-ce) for Railway: persistent server GPG key, JWT keypair and avatars on one volume, database login baked in, and a first administrator created from variables at first boot with a setup link derived from `PASSBOLT_SETUP_SECRET`.

Built by GitHub Actions and published to `ghcr.io/bon5co/passbolt-railway`. Template source and listing notes: the `passbolt/` folder of the Railway templates repository.
