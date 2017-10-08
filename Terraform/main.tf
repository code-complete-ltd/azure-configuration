#######################
### RESOURCE GROUPS ###
#######################

resource "azurerm_resource_group" "infrastructure" {
  name     = "${var.env_short_name}-infrastructure-rg"
  location = "${var.location_name}"
  tags {
    environment = "${var.env_name}"
  }
}

resource "azurerm_resource_group" "web" {
  name     = "${var.env_short_name}-web-rg"
  location = "${var.location_name}"
  tags {
    environment = "${var.env_name}"
  }
}

########################
### STORAGE ACCOUNTS ###
########################

resource "azurerm_storage_account" "primary" {
  name                = "codecomplete${var.env_short_name}"
  resource_group_name = "${azurerm_resource_group.infrastructure.name}"
  location            = "${var.location_name}"
  account_type        = "Standard_LRS"
  tags {
    environment = "${var.env_name}"
  }
}

##################
### PUBLIC IPS ###
##################

resource "azurerm_public_ip" "primary" {
  name                         = "${var.env_short_name}-ip"
  location                     = "${var.location_name}"
  resource_group_name          = "${azurerm_resource_group.infrastructure.name}"
  public_ip_address_allocation = "static"
  domain_name_label            = "code-complete-${var.env_short_name}"
}

######################
### LOAD BALANCERS ###
######################

resource "azurerm_lb" "primary" {
  name                = "${var.env_short_name}-lb"
  location            = "${var.location_name}"
  resource_group_name = "${azurerm_resource_group.infrastructure.name}"
  frontend_ip_configuration {
    name                 = "primary-ip-config"
    public_ip_address_id = "${azurerm_public_ip.primary.id}"
  }
}

###########################################
### LOAD BALANCER BACKEND ADDRESS POOLS ###
###########################################

resource "azurerm_lb_backend_address_pool" "web" {
  resource_group_name = "${azurerm_resource_group.infrastructure.name}"
  loadbalancer_id     = "${azurerm_lb.primary.id}"
  name                = "web"
}

############################
### LOAD BALANCER PROBES ###
############################

resource "azurerm_lb_probe" "http" {
  resource_group_name = "${azurerm_resource_group.infrastructure.name}"
  loadbalancer_id     = "${azurerm_lb.primary.id}"
  name                = "http"
  port                = 80
}

resource "azurerm_lb_probe" "https" {
  resource_group_name = "${azurerm_resource_group.infrastructure.name}"
  loadbalancer_id     = "${azurerm_lb.primary.id}"
  name                = "https"
  port                = 443
}

###########################
### LOAD BALANCER RULES ###
###########################

resource "azurerm_lb_rule" "http" {
  resource_group_name            = "${azurerm_resource_group.infrastructure.name}"
  loadbalancer_id                = "${azurerm_lb.primary.id}"
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "primary-ip-config"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.web.id}"
  probe_id                       = "${azurerm_lb_probe.http.id}"
}

resource "azurerm_lb_rule" "https" {
  resource_group_name            = "${azurerm_resource_group.infrastructure.name}"
  loadbalancer_id                = "${azurerm_lb.primary.id}"
  name                           = "https"
  protocol                       = "Tcp"
  frontend_ip_configuration_name = "primary-ip-config"
  frontend_port                  = 443
  backend_port                   = 443
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.web.id}"
  probe_id                       = "${azurerm_lb_probe.https.id}"
}

###############################
### LOAD BALANCER NAT RULES ###
###############################

resource "azurerm_lb_nat_rule" "ssh" {
  resource_group_name            = "${azurerm_resource_group.infrastructure.name}"
  loadbalancer_id                = "${azurerm_lb.primary.id}"
  name                           = "ssh"
  protocol                       = "Tcp"
  frontend_ip_configuration_name = "primary-ip-config"
  frontend_port                  = 22
  backend_port                   = 22
}

################
### NETWORKS ###
################

resource "azurerm_virtual_network" "primary" {
  name                = "${var.env_short_name}-net"
  resource_group_name = "${azurerm_resource_group.infrastructure.name}"
  address_space       = ["172.16.0.0/16"]
  location            = "${var.location_name}"
  dns_servers         = ["8.8.8.8"]
  tags {
    environment = "${var.env_name}"
  }
}

###############
### SUBNETS ###
###############

resource "azurerm_subnet" "web" {
  name                      = "web"
  resource_group_name       = "${azurerm_resource_group.infrastructure.name}"
  virtual_network_name      = "${azurerm_virtual_network.primary.name}"
  network_security_group_id = "${azurerm_network_security_group.web.id}"
  address_prefix            = "172.16.1.0/24"
}

###############################
### NETWORK SECURITY GROUPS ###
###############################

resource "azurerm_network_security_group" "web" {
  name                = "${var.env_short_name}-web-nsg"
  location            = "${var.location_name}"
  resource_group_name = "${azurerm_resource_group.infrastructure.name}"
  security_rule {
    name                       = "AllowAll"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags {
    environment = "${var.env_name}"
  }
}

##########################
### NETWORK INTERFACES ###
##########################

resource "azurerm_network_interface" "web" {
  count               = 1
  name                = "${var.env_short_name}-web${format("%02d", count.index + 1)}-ni"
  location            = "${var.location_name}"
  resource_group_name = "${azurerm_resource_group.web.name}"
  ip_configuration {
    name                                    = "primary-ip-config"
    subnet_id                               = "${azurerm_subnet.web.id}" 
    private_ip_address_allocation           = "dynamic"
    load_balancer_backend_address_pools_ids = ["${azurerm_lb_backend_address_pool.web.id}"]
    load_balancer_inbound_nat_rules_ids     = ["${azurerm_lb_nat_rule.ssh.id}"]
  }
  tags {
    environment = "${var.env_name}"
  }
}

#########################
### AVAILABILITY SETS ###
#########################

resource "azurerm_availability_set" "web" {
  name                        = "${var.env_short_name}-web-as"
  location                    = "${var.location_name}"
  resource_group_name         = "${azurerm_resource_group.web.name}"
  managed                     = true
  platform_fault_domain_count = 2
  tags {
    environment = "${var.env_name}"
  }
}

########################
### VIRTUAL MACHINES ###
########################

resource "azurerm_virtual_machine" "web" {
  count                 = 1
  name                  = "${var.env_short_name}-web${format("%02d", count.index + 1)}-vm"
  location              = "${var.location_name}"
  availability_set_id   = "${azurerm_availability_set.web.id}"
  resource_group_name   = "${azurerm_resource_group.web.name}"
  network_interface_ids = ["${element(azurerm_network_interface.web.*.id, count.index)}"]
  vm_size               = "Standard_A2_v2"
  boot_diagnostics {
    enabled = true
    storage_uri = "${azurerm_storage_account.primary.primary_blob_endpoint}"
  }
  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "${var.env_short_name}-web${format("%02d", count.index + 1)}-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "web${format("%02d", count.index + 1)}"
    admin_username = "fraser"
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys                        = [
      {
          path     = "/home/fraser/.ssh/authorized_keys"
          key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC2vlMUFRhbged6eP4jUQQgJyDUB2SFFojOov2nR4957SNXpcRKhT6HHSPVLI9FfBB4YRjMC3qseQOtS2QncnL+ZbZuSxybkqy5XGCO7zQs9TGEUwf8YPWXR9JTKxFOtL4+s4ucr4YKZkNkysjMl1R2NjcE3fKbHym6bGA0KTNguTBtGe5hipn4utmpQTS4tvJkm2Ny+XeEGTYd2v1d40A9QU614vTzKtOG56acrwG7B2jdGLlSbFamhW9kS6QEGDWhkc6wqkSM8Uly4TLLSYlHJLe5KnZpXnY9+LxXaEW0KpRXuewjpz1Sq46tgwqoDq18q17l6xuG9+ggNGpK0LrZ"
      }
    ]
  }
  tags {
    environment = "${var.env_name}"
  }
}
