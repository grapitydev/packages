# grapity packages

Static package repository hosting for the [grapity](https://github.com/grapitydev/grapity) CLI: apt (Debian/Ubuntu), dnf (Fedora/RHEL), and pacman (Arch) repositories, served at [packages.grapity.dev](https://packages.grapity.dev) via GitHub Pages.

The published site lives on the `gh-pages` branch and is rebuilt from scratch on every release by the `packages` job in `.github/workflows/binaries.yml` of the grapity repo. Only the latest release is kept. The custom domain is preserved across publishes by a `CNAME` file written on every deploy; the legacy `grapitydev.github.io/packages` URLs redirect here.

## Signing

All repository metadata is signed with the Grapity Releases GPG key (`gpg.key` in this repo, also published at the site root):

```
Grapity Releases <contact@grapity.dev>
Fingerprint: 40D5 A375 F72A 82BD 6F2A A664 5BC0 2278 C130 6FA1
```

## Install

### apt (Debian/Ubuntu)

```sh
curl -fsSL https://packages.grapity.dev/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grapity.gpg
echo "deb [signed-by=/usr/share/keyrings/grapity.gpg] https://packages.grapity.dev/apt stable main" | sudo tee /etc/apt/sources.list.d/grapity.list
sudo apt update && sudo apt install grapity
```

### dnf (Fedora/RHEL)

```sh
sudo dnf config-manager addrepo --from-repofile=https://packages.grapity.dev/dnf/grapity.repo
sudo dnf install grapity
```

### pacman (Arch)

Append to `/etc/pacman.conf`:

```ini
[grapity]
SigLevel = Required DatabaseOptional
Server = https://packages.grapity.dev/pacman/$arch
```

Then:

```sh
sudo pacman-key --add <(curl -fsSL https://packages.grapity.dev/gpg.key)
sudo pacman-key --lsign-key contact@grapity.dev
sudo pacman -Sy grapity
```
