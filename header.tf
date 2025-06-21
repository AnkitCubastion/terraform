terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.34.0"
    }
  }
}


provider "azurerm" {
  subscription_id = "0fd48776-0395-4bd9-b209-cd657e8be24d"
  client_id       = "d57a0afc-01fe-457b-99df-02c2eeb8dc5f"
  client_secret   = "ani8Q~BPoumGTyiVA5yjUZkvM.3gP0Je-NZF2ald"
  tenant_id       = "d032994e-e52c-4d44-bc79-9fd88e88ad02"
  features {}
}
