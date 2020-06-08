# GitLab SSH Proxy

One if the issue with running a GitLab instance in a container is to expose the GitLab SSH in the host machine without conflicting with the existing SSH port (22) on the host.

What usually happens:

```
git://git@hostname:2222/username/project.git  
```

We want them to look like this instead:

```
git://git@hostname/username/project.git  
```

There are several alternatives online (see References below). But I would like to avoid:
- Hardcoding the UID and GID of any account in the host machine
- Running additional services/daemon in the host machine
- Providing Docker access to a special account in the host machine
- Duplicating GitLab's `authorized_keys` files in the host machine

For a detailed explanation, see the [How Does It Work](#how-does-it-work) section below.

## Step by Step

Build and install.

```
sudo ./setup.sh install
```

It will do the following things:
1. Copy the follwoing scripts to `/usr/local/bin`
    - [`gitlab-keys-check`](gitlab-keys-check)
    - [`gitlab-shell-proxy`](gitlab-shell-proxy)
1. Build and install an SE Linux policy module: [`gitlab-ssh.te`](gitlab-ssh.te) to allow scripts executed from the SSH daemon to run the `ssh` binary.

Create the `git` user on the host

```bash
sudo useradd -m git
```

Create a new SSH key-pair

```bash
sudo su - git -c "ssh-keygen -t ed25519"
```

Assuming run the container with `--volume /srv/gitlab/ssh:/gitlab-data/ssh:Z`, copy and rename the public key to `/srv/gitlab/ssh/authorized_keys`.

```bash
sudo cp /home/git/.ssh/id_ed25519.pub /srv/gitlab/ssh/authorized_keys
```

Fix the permission/ownership of the `authorized_keys` file to ensure that is only readable by the `git` user within the container. Otherwise SSH won't use the file.

```bash
# If you are using Docker, substitute podman with docker
podman exec -it gitlab /bin/sh -c \
    "chmod 600 /gitlab-data/ssh/authorized_keys; chown git:git /gitlab-data/ssh/authorized_keys"
```

Open `/etc/ssh/sshd_config` and add the following lines:

```ssh-config
Match User git
    PasswordAuthentication no
    AuthorizedKeysCommand /usr/local/bin/gitlab-keys-check git %u %k
    AuthorizedKeysCommandUser git
```

Reload the SSH Service

```bash
sudo systemctl reload sshd
```

You're good to go!

### Configuration

By the default the scripts assumes that the GitLab SSH service is accessible at `git@localhost` port `2222`. If your setup is different, you can override this by creating a file named `gitlab-ssh.conf` in `/home/git/.config` or `/etc`.

In this file you can define the following environment variables:

```bash
GITLAB_HOST=git@localhost
GITLAB_PORT=2222
```

## Uninstall

This will remove all the script files and the SE Linux proxy module.

```
sudo ./setup.sh remove
```

Don't forget to remove the additonal configuration in `/etc/ssh/sshd_config`

## <a name="how-does-it-work"></a>How Does it Work

First we would need to have a `git` user in the host machine. When a user connects via SSH, it should be able to somehow redirect/forward the request as the `git` user in the container.

GitLab authenticates users based on their SSH keys. This is traditionally done by adding the user's public key into an `authorized_keys` file. Recently GitLab foregoes this file and uses a database instead. To do this GitLab uses a feature in the Open SSH server called [`AuthorizedKeysCommand`](https://manpages.debian.org/unstable/openssh-server/sshd_config.5.en.html#AuthorizedKeysCommand) which allows it to execute a program to query its keys database and return the relevant key data.

In the host, we do the same thing. We configure the `AuthorizedKeysCommand` to call our [`gitlab-keys-check`](gitlab-keys-check) script when someone tries to login as `git`. This script runs `ssh` to the container (via port 2222) and execute the actual tool, `gitlab-shell-authorized-keys-check`. It would return an `authorized_keys` entries which looks like this:

```
command="/opt/gitlab/embedded/service/gitlab-shell/bin/gitlab-shell key-1",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJEO... username@hostname
```

The `command` option at the beginning forces the SSH server to execute `/opt/.../bin/gitlab-shell` when the key is used to login. This command does not exist in the host machine. Therefore before we return it we must replace this with [`/usr/local/bin/gitlab-shell-proxy`](gitlab-shell-proxy).

```
command="/usr/local/bin/gitlab-shell-proxy key-1",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJEO... username@hostname
```

The SSH server will see the updated command and execute `gitlab-shell-proxy`. This script will run `ssh` again and execute the orginal binary `/opt/.../bin/gitlab-shell`, effectively creating a proxy to the GitLab container.

For this to work, the `git` user in the host would need to have an `authorized_key` in the GitLab container. Therefore copy its public key file into `/gitlab-data/ssh/authorized_keys` in the container. We also need to adjust the file permission as Open SSH is quite strict about it.

There is one complication. In machines with SE Linux enabled, we are unable to execute `ssh` from the `AuthorizedKeysCommand`. To workaround this, we would need to install a custom policy file [`gitlab-ssh.te`](gitlab-ssh.te) to enable this. 

## References
- https://blog.xiaket.org/2017/exposing.ssh.port.in.dockerized.gitlab-ce.html
- http://www.ateijelo.com/blog/2016/07/09/share-port-22-between-docker-gogs-ssh-and-local-system
- https://github.com/sameersbn/docker-gitlab/issues/1517#issuecomment-368265170
- https://forge.monarch-pass.net/monarch-pass/gitlab-ssh-proxy
- https://manpages.debian.org/unstable/openssh-server/sshd_config.5.en.html