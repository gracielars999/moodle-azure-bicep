# 🎓 Moodle on Azure — Production Infrastructure

Plantillas Bicep para desplegar Moodle en Azure con arquitectura de producción basada en:
- **VMSS** (Windows Server 2022 + IIS + PHP 8.2) con autoscale
- **Azure Front Door Premium** con WAF, certificado TLS manejado y Private Link
- **Azure Database for MySQL Flexible Server** con Alta Disponibilidad zona-redundante
- **Azure Cache for Redis** para sesiones y caché
- **Azure Files Premium** para almacenamiento compartido de moodledata
- **Azure Key Vault** para gestión de secretos
- **VM Controladora** para cron de Moodle y jumpbox de administración
- **Azure Bastion** para acceso RDP seguro

---

## 🚀 Despliegue con un clic

Haz clic en el botón para abrir el portal de Azure con los parámetros precargados:

[![Deploy to Azure](https://aka.ms/deploytoazure)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgracielars999%2Fmoodle-azure-bicep%2Fmain%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fgracielars999%2Fmoodle-azure-bicep%2Fmain%2Fazuredeploy.json)

---

## 🏗️ Arquitectura

```
                        Internet
                           ↓
              ┌─────────────────────────┐
              │   Azure Front Door      │
              │   Premium + WAF         │
              │   Managed TLS Cert      │
              └────────────┬────────────┘
                           │ Private Link
                           ↓
              ┌─────────────────────────────────────┐
              │         VNet (10.0.0.0/16)          │
              │                                     │
              │  Internal Load Balancer             │
              │        ↓                            │
              │  VM Scale Set (VMSS)                │
              │  Windows Server 2022 + IIS + PHP    │
              │  Standard_D4s_v5 · min:2 max:4      │
              │                                     │
              │  VM Controladora (B2s)              │
              │  Cron · Jumpbox · Deploy            │
              │                                     │
              │  MySQL Flexible Server (D2ds_v4)    │
              │  Redis C1 Standard                  │
              │  Azure Files Premium 512 GB         │
              │  Key Vault · Azure Bastion          │
              └─────────────────────────────────────┘
```

---

## 📋 Parámetros requeridos

| Parámetro | Descripción | Ejemplo |
|---|---|---|
| `prefix` | Prefijo para todos los recursos | `moodle` |
| `location` | Región de Azure | `eastus` |
| `adminUsername` | Usuario administrador de las VMs | `azureadmin` |
| `adminPassword` | Contraseña de las VMs (mín. 12 chars) | `***` |
| `mysqlAdminUsername` | Usuario admin MySQL | `moodleadmin` |
| `mysqlAdminPassword` | Contraseña MySQL | `***` |
| `customDomain` | Dominio público para Moodle | `moodle.tudominio.com` |
| `moodleDbName` | Nombre de la base de datos | `moodle` |

---

## 🛠️ Despliegue manual desde PowerShell (Windows)

### Prerrequisitos
- [Azure CLI](https://aka.ms/installazurecliwindows)
- [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install) (`az bicep install`)
- PowerShell 5.1 o superior

### Pasos

```powershell
# 1. Autenticarse en Azure
az login

# 2. Crear el Resource Group
az group create --name rg-moodle-prod --location eastus

# 3. Clonar este repositorio
git clone https://github.com/gracielars999/moodle-azure-bicep.git
cd moodle-azure-bicep

# 4. Editar parameters.bicepparam con tus valores
notepad parameters.bicepparam

# 5. Validar antes de desplegar
az deployment group validate `
  --resource-group rg-moodle-prod `
  --template-file main.bicep `
  --parameters parameters.bicepparam

# 6. Desplegar (~25-35 minutos)
az deployment group create `
  --resource-group rg-moodle-prod `
  --template-file main.bicep `
  --parameters parameters.bicepparam `
  --verbose

# 7. Ver outputs (FQDN, endpoints, nombres de recursos)
az deployment group show `
  --resource-group rg-moodle-prod `
  --name main `
  --query properties.outputs `
  --output table
```

---

## 📦 Estructura del repositorio

```
├── main.bicep                  # Orquestador principal
├── parameters.bicepparam       # Archivo de parámetros de ejemplo
├── azuredeploy.json            # ARM JSON compilado (para Deploy to Azure)
├── modules/
│   ├── network.bicep           # VNet, subnets, NSGs
│   ├── mysql.bicep             # MySQL Flexible Server + DNS privado
│   ├── redis.bicep             # Azure Cache for Redis + private endpoint
│   ├── storage.bicep           # Azure Files Premium
│   ├── keyvault.bicep          # Key Vault + RBAC
│   ├── compute.bicep           # VMSS + ILB + Private Link + Controller VM
│   ├── frontdoor.bicep         # Front Door Premium + WAF + certificado
│   └── bastion.bicep           # Azure Bastion Basic
└── scripts/
    ├── setup-moodle-node.ps1   # Configura IIS/PHP en nodos VMSS
    └── setup-controller.ps1    # Configura VM controladora + cron Moodle
```

---

## ✅ Pasos post-despliegue

Una vez terminado el despliegue en Azure, debes realizar estos pasos manuales:

### 1. Configurar DNS
En tu proveedor de DNS (GoDaddy, Cloudflare, etc.), agrega un registro:
```
CNAME  moodle.tudominio.com  →  <valor de frontDoorEndpoint en outputs>
```
El certificado TLS se generará automáticamente (~5-10 minutos).

### 2. Aprobar Private Endpoint
En el **Portal de Azure**:
> Private Link Center → Pending connections → **Approve**

Esto conecta Front Door Premium con el Internal Load Balancer de forma privada.

### 3. Instalar Moodle (wizard web)
1. Conéctate a la **VM Controladora** via Azure Bastion (Portal → Bastion)
2. El script ya descargó Moodle en `C:\moodle\html` y montó Azure Files como `Z:\`
3. Abre `https://moodle.tudominio.com` en el browser
4. Sigue el wizard de instalación:
   - **Data directory**: `Z:\moodledata`
   - **DB host**: valor de `mysqlFQDN` del output
   - **DB name**: `moodle`
   - **DB user/pass**: los que definiste en los parámetros

### 4. Sincronizar código a nodos VMSS
Después de completar el wizard, sincroniza el `config.php` generado a todos los nodos:
```powershell
# Desde la VM Controladora
$vmssNodes = @("10.0.1.4", "10.0.1.5")  # IPs de los nodos
foreach ($node in $vmssNodes) {
    robocopy C:\moodle\html \\$node\c$\moodle\html config.php
}
```

### 5. Configurar Redis en Moodle
En `config.php`, agrega:
```php
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = '<redis-fqdn>';
$CFG->session_redis_port = 6380;
$CFG->session_redis_auth = '<redis-key-from-keyvault>';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;
```

---

## 💰 Estimación de costo mensual

| Recurso | SKU | $/mes aprox |
|---|---|---|
| Front Door Premium | Standard | ~$330 |
| VMSS 2× D4s_v5 Windows | Base (2 nodos) | ~$350 |
| VM Controladora B2s Windows | Standard | ~$35 |
| MySQL Flexible D2ds_v4 HA | Zone-redundant | ~$180 |
| Redis C1 Standard | Standard | ~$55 |
| Azure Files Premium 512 GB | Premium | ~$55 |
| Key Vault Standard | Standard | ~$5 |
| Azure Bastion Basic | Basic | ~$140 |
| Private Endpoints ×4 | — | ~$30 |
| **Total estimado base** | | **~$1,180 USD/mes** |

> Los costos varían según región y consumo real. Consulta [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/).

---

## 🔒 Seguridad

- ✅ Todo el tráfico al backend viaja por **Private Link** (nunca internet)
- ✅ MySQL, Redis y Key Vault solo accesibles dentro del VNet (private endpoints)
- ✅ NSGs en todas las subnets con reglas de mínimo privilegio
- ✅ Azure Bastion para RDP seguro sin IPs públicas en las VMs
- ✅ WAF en Front Door con reglas OWASP 3.2 en modo Prevention
- ✅ TLS 1.2 mínimo en todos los servicios
- ✅ Managed Identity en VMSS y Controller VM (sin credenciales en código)

---

## 📚 Referencias

- [Azure/Moodle - Repositorio oficial](https://github.com/Azure/Moodle)
- [Moodle Performance Recommendations](https://docs.moodle.org/en/Performance_recommendations)
- [Azure Front Door Premium + Private Link](https://learn.microsoft.com/en-us/azure/frontdoor/private-link-overview)
- [Azure Database for MySQL Flexible Server](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/)

---

## 📄 Licencia

MIT License — libre para uso y modificación.
