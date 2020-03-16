# Adds passwordless sudo for either the WHEEL or SUDO group.

Upload it locally to a server and run it, or run it remotely from the local file, like so:

__Ubuntu:__
```
ssh <USER@SERVER> 'sudo bash -s' < ./passwordless-sudo.sh sudo
```

__Red Hat / CentOS__
```
ssh <USER@SERVER> 'sudo bash -s' < ./passwordless-sudo.sh wheel
```
