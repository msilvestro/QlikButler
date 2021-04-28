# Qlik Butler

Qlik Butler makes it easy to manage your Qlik Sense and NPrinting clusters.

It is composed of two parts:

- **Qlik Butler** itself, which performs various tasks on every node of each cluster, such as (but not limited to):
  - services restart;
  - app and extension import;
  - backup.
- **Qlik Butler Manager**, which keeps under control all clusters from a single interface and allows to install, uninstall and update all Qlik Butler installations. Must be installed on a server that has access to all of the above clusters.

## Configuration files

You should place two configuration files in the `Data` directory.

### List of clusters

The file `Data/NodiCluster.csv` contains the list of clusters in the same domain that the Qlik Butler Manager server should manage.
The information needed are:

- **Acronimo**: Name of the cluster.
- **Ambiente**: Type of environment, usually may be Production, Laboratory, System Test or Development.
- **Hostname**: Hostname of the node.
- **Installazione**: Type of installation, i.e. Qlik Sense or NPrinting.
- **TipoNode**: Node type, i.e. Central or Rim.

Example file:

```
Acronimo;Ambiente;Hostname;Installazione;TipoNodo
QLK;Prod;hostname1;Qlik Sense;Central
QLK;Prod;hostname2;Qlik Sense;Rim
NPR;Labo;hostname3;NPrinting;Central
NPR;Labo;hostname4;NPrinting;Rim
```

### System configuration

The file `Data/System.config` contains your system specific configuration, that is:

- Windows Qlik Sense services administrator user name and password.
- PostgreSQL database superuser user name and password.
- Shared folder in which the backups should be located.

Example file:

```
QlikAdministratorUser = DOMAIN\qlikadministrator
QlikAdministratorPassword = qlikadministratorpassword
RepositoryUser = postgres
RepositoryPassword = repositorypassword
BackupRoot = \\shared\folder\backup\root
```

## Backstory

I worked for some time as a Qlik Sense and NPrinting system administrator. To ease the need for trivial and recurring tasks characteristic of this job, I harnessed the power of [Qlik-Cli][qcli] to create an automation scripts suite. From this small core I started to build the foundation of a bigger project, that also included a graphical user interface, written in PowerShell.

[qcli]: https://github.com/ahaydon/Qlik-Cli
