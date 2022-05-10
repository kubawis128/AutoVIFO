#!/bin/bash

##############################
#                            #
#  Setup basic virt-manager  #
#                            #
##############################

pacman -S libvirt edk2-ovmf virt-manager dnsmasq ebtables zenity
systemctl enable --now libvirtd
usermod -aG kvm,input,libvirt `whoami`


##############################
#                            #
#  Create hooks for machine  #
#                            #
##############################

mkdir /etc/libvirt/hooks
touch /etc/libvirt/hooks/qemu
chmod +x /etc/libvirt/hooks/qemu

cat <<- EOF > /etc/libvirt/hooks/qemu 
#!/bin/bash

GUEST_NAME="$1"
HOOK_NAME="$2"
STATE_NAME="$3"
MISC="${@:4}"

BASEDIR="$(dirname $0)"

HOOKPATH="$BASEDIR/qemu.d/$GUEST_NAME/$HOOK_NAME/$STATE_NAME"
set -e # If a script exits with an error, we should as well.

if [ -f "$HOOKPATH" ]; then
eval \""$HOOKPATH"\" "$@"
elif [ -d "$HOOKPATH" ]; then
while read file; do
  eval \""$file"\" "$@"
done <<< "$(find -L "$HOOKPATH" -maxdepth 1 -type f -executable -print;)"
fi
EOF

##############################
#                            #
#  Ask what is machine name  #
#                            #
##############################

export machine=$(zenity --entry --title="What is the VM's name" --text="Name of VIFO machine:" --entry-text "name")

##############################
#                            #
# Ask what GPU to passtrough #
#                            #
##############################


mkdir -p /etc/libvirt/hooks/qemu.d/`echo $machine`/prepare/begin
touch /etc/libvirt/hooks/qemu.d/`echo $machine`/prepare/begin/start.sh
chmod +x /etc/libvirt/hooks/qemu.d/`echo $machine`/prepare/begin/start.sh

export out=
export i=
rm vifo.tmp
lspci | grep "VGA" | while read line 
do
   let "i+=1"
   export out=$(echo -n $out; echo -n "\""$i $line "\"")
   export out=$(echo $out | sed 's/""/" "/')
   echo $out > vifo.tmp
done
cat vifo.tmp
export result=$(eval $(echo -n "zenity --list --title=\"Choose the Bugs You Wish to View\" --column \"Device\" "; cat vifo.tmp;))


export huj=$(echo `lspci  | grep -oP '.*VGA' | sed 's/\./_/g' | sed 's/\:/_/g' | cut -c1-8` | sed 's/\x20/,/')
IFS="," read -r -a array <<< `echo $huj`
export GPU=`echo ${array[((${result:0:1}-1))]}`

export out=
export i=
rm vifo.tmp
lspci | grep "Audio" | while read line 
do
   let "i+=1"
   export out=$(echo -n $out; echo -n "\""$i $line "\"")
   export out=$(echo $out | sed 's/""/" "/')
   echo $out > vifo.tmp
done
cat vifo.tmp
export result=$(eval $(echo -n "zenity --list --title=\"Choose the Bugs You Wish to View\" --column \"Device\" "; cat vifo.tmp;))


export huj=$(echo `lspci  | grep -oP '.*Audio' | sed 's/\./_/g' | sed 's/\:/_/g' | cut -c1-8` | sed 's/\x20/,/')
IFS="," read -r -a array <<< `echo $huj`
export AUDIO=`echo ${array[((${result:0:1}-1))]}`



cat <<- EOF > /etc/libvirt/hooks/qemu.d/`echo $machine`/prepare/begin/start.sh
#!/bin/bash
set -x

# Stop display manager
systemctl stop display-manager
systemctl stop gdm
    
# Unbind VTconsoles: might not be needed
echo 0 > /sys/class/vtconsole/vtcon0/bind
echo 0 > /sys/class/vtconsole/vtcon1/bind

# Unbind EFI Framebuffer
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

# Unload NVIDIA kernel modules
modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia

# Unload AMD kernel module
modprobe -r amdgpu

# Detach GPU devices from host
# Use your GPU and HDMI Audio PCI host device

virsh nodedev-detach pci_0000_`echo $GPU`

virsh nodedev-detach pci_0000_`echo $AUDIO`

# Load vfio module
modprobe vfio-pci
EOF

mkdir -p /etc/libvirt/hooks/qemu.d/`echo $machine`/release/end
touch /etc/libvirt/hooks/qemu.d/`echo $machine`/release/end/stop.sh
chmod +x /etc/libvirt/hooks/qemu.d/`echo $machine`/release/end/stop.sh

cat <<- EOF > /etc/libvirt/hooks/qemu.d/`echo $machine`/release/end/stop.sh
#!/bin/bash
set -x

# Unload vfio module
modprobe -r vfio-pci

# Attach GPU devices to host
# Use your GPU and HDMI Audio PCI host device
virsh nodedev-reattach pci_0000_`echo $GPU`
virsh nodedev-reattach pci_0000_`echo $AUDIO`

# Rebind framebuffer to host
echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind

# Load NVIDIA kernel modules
modprobe nvidia_drm
modprobe nvidia_modeset
modprobe nvidia_uvm
modprobe nvidia

# Load AMD kernel module
modprobe amdgpu
    
# Bind VTconsoles: might not be needed
echo 1 > /sys/class/vtconsole/vtcon0/bind
echo 1 > /sys/class/vtconsole/vtcon1/bind

# Restart Display Manager
systemctl start display-manager
systemctl start gdm
EOF
