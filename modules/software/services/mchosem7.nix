# Udev to allow hid access for Mchose web driver
{
  services.udev.extraRules = ''
    KERNEL=="hidraw*", ATTRS{idVendor}=="5253", ATTRS{idProduct}=="0031", MODE="0664", GROUP="input"
    KERNEL=="hidraw*", ATTRS{idVendor}=="5253", ATTRS{idProduct}=="1020", MODE="0664", GROUP="input"
  '';
}
