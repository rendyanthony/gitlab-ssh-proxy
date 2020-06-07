# GitLab SSH Proxy

One if the issue with running a GitLab instance in a container is to expose the GitLab SSH in the host machine without conflicting with the existing SSH port (22) on the host. There are several alternatives online (see References below) but I believe there must be a more elegant way. Something that avoids:
- Hardcoding the UID and GID of any account in the host machine
- Running additional services/daemon in the host machine
- Duplicating GitLab's `authorized_keys` files in the host machine
- Using `iptables`
- Providing Docker access to an account

## Background

Here is how I run my GitLab container. I am using `podman` on Fedora, but it shouldn't make much different if you're using Docker.

```
podman run --detach
    --hostname gitlab
    --publish 8443:443 --publish 8080:80 --publish 2222:22
    --name gitlab
    --volume /srv/gitlab/config:/etc/gitlab:Z
    --volume /srv/gitlab/logs:/var/log/gitlab:Z
    --volume /srv/gitlab/data:/var/opt/gitlab:Z
    --volume /srv/gitlab/ssh:/gitlab-data/ssh:Z
    gitlab/gitlab-ce:latest
```

As you can see GitLab SSH service is mapped to port 2222 in the host machine. What we want to do is for a user to access the GitLab repo without using a non-standard port on the host machine. While at the same time keep the standard SSH access in the host machine for other non-git related access.

## Installation

Build and install the package

```
sudo ./setup.sh install
```

This will do the following things:
1. Copy the follwoing scripts to `/usr/local/bin`
    - [`gitlab-keys-check`](gitlab-keys-check)
    - [`gitlab-shell-proxy`](gitlab-shell-proxy)
1. Install an SE Linux policy module: [`gitlab-ssh.te`](gitlab-ssh.te) to allow scripts executed from the SSH server to establish an SSH connection

### Configuration

By the default the script assumes that the GitLab SSH service is accessible at `git@localhost` port `2222`. If your setup is different, you can override this by creating a file named `gitlab-ssh.conf` in `/home/git/.config` or `/etc`.

In this file you can define the following environment variables:

```bash
GITLAB_URL=git@localhost
GITLAB_PORT=2222
```

## Host Setup

Create the `git` user on the host

```bash
sudo useradd -m git
```

Create a new SSH key-pair

```bash
sudo su - git -c "ssh-keygen -t ed25519"
```

This will generate two files:
 - `/home/git/.ssh/id_ed25519` &mdash; Private Key
 - `/home/git/.ssh/id_ed25519.pub` &mdash; Public Key

Modify `/etc/ssh/sshd_config` to add the following lines.

```ssh-config
Match User git
    PasswordAuthentication no
    AuthorizedKeysCommand /usr/local/bin/gitlab-keys-check git %u %k
    AuthorizedKeysCommandUser git
```

The key ingredient here is the usage of [`AuthorizedKeysCommand`](https://manpages.debian.org/unstable/openssh-server/sshd_config.5.en.html#AuthorizedKeysCommand). This will allow us to validate the user's key using a script instead of a pre-defined `authorized_keys` file.

We would need to reload the SSH service to apply the configuration change.

```bash
sudo systemctl reload sshd
```

## Container Setup

Copy the public key into `/gitlab-data/ssh/` inside the container. In my setup this directory mounted from `/srv/gitlab/ssh` in the host. Therefore we simply copy the file there.

```bash
sudo cp /home/git/.ssh/id_ed25519.pub /srv/gitlab/ssh/authorized_keys
```

Finally, fix the permission/ownership of the file to ensure that is only readable by the `git` user within the container.

```bash
podman exec -it gitlab /bin/sh -c \
    "chmod 600 /gitlab-data/ssh/authorized_keys; chown git:git /gitlab-data/ssh/authorized_keys"
```

As the command will modifies the permission of a file in the host, the change will persist over different containers.

## Testing

Test the connection:

```
$ ssh git@localhost
PTY allocation request failed on channel 0
Welcome to GitLab, @user!
Connection to localhost closed.
```

## Uninstall

This will remove all the script files and the SE Linux proxy module.

```
sudo ./setup.sh remove
```

Don't forget to remove the additonal configuration in `/etc/ssh/sshd_config`

## References

- https://blog.xiaket.org/2017/exposing.ssh.port.in.dockerized.gitlab-ce.html
- https://github.com/sameersbn/docker-gitlab/issues/1517#issuecomment-368265170
- https://forge.monarch-pass.net/monarch-pass/gitlab-ssh-proxy
- https://manpages.debian.org/unstable/openssh-server/sshd_config.5.en.html