# QlikButler
Qlik Butler makes it easy to manage your Qlik Sense and NPrinting clusters.

## Configuration files

You should place two configuration files in the `Data` directory.

### List of clusters

The file `Data/NodiCluster.csv` contains the list of clusters in the same domain that the Qlik Butler Manager server should manage.
The information needed are:
* **Acronimo**: Name of the cluster.
* **Ambiente**: Type of environment, usually may be Production, Laboratory, System Test or Development.
* **Hostname**: Hostname of the node.
* **Installazione**: Type of installation, i.e. Qlik Sense or NPrinting.
* **TipoNode**: Node type, i.e. Central or Rim.

Example file:
```
Acronimo;Ambiente;Hostname;Installazione;TipoNodo
ACRO0;Prod;hostname001;Qlik Sense;Central
ACRO0;Prod;hostname002;Qlik Sense;Rim
NPRI0;Labo;hostname003;NPrinting;Central
NPRI0;Labo;hostname003;NPrinting;Rim
```

### System configuration

The file `Data/System.config` contains your system specific configuration, that is:
* Windows Qlik Sense services administrator user name and password.
* PostgreSQL database superuser user name and password.
* Shared folder in which the backups should be located.

Example file:
```
QlikAdministratorUser = DOMAIN\qlikadministrator
QlikAdministratorPassword = qlikadministratorpassword
RepositoryUser = postgres
RepositoryPassword = repositorypassword
BackupRoot = \\shared\folder\backup\root
```
