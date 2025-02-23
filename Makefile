include $(PROJECT)/make.env

VCPUS ?= 2
RAM_MB ?= 2048
DISK_GB ?= 10
IMAGE ?= $(PWD)/coreos.qcow2

IGNITION_PATH = /home/$(USER)/.config/libvirt/ignition/$(PROJECT).ign
STREAM = stable

# Targets
.PHONY: all clean clean-ignite ignite launch destroy shutdown delete ssh clean-download download

all: launch

# This will check if the domain already exists. Used to prevent some action that will fail anyway.
fail-if-vm-exists:
	@sudo virsh domid $(VM_NAME) 2>/dev/null; \
	status=$$?; \
	if [ $$status -eq 0 ]; then \
		echo "Error: The VM already exists. Changing the configuration is not allowed. Run make delete to remove the domain first."; \
		exit 1; \
	fi

# Removes the generated files. Will fail if the domain already exists because the ignite is only executed 
# on first boot but the VM needs the file to boot.
clean-ignite: fail-if-vm-exists
	@rm -f $(PROJECT)/generated-butane.conf /home/$(USER)/.config/libvirt/ignition/$(PROJECT).ign


# Cleans the generated files and then generates the new butane and ignite files.
ignite: clean-ignite $(PROJECT)/generated-butane.conf


# Converst the template to a final butane configuration, then generates an ignite file.
$(PROJECT)/generated-butane.conf:
	IGN_HOSTNAME=$(IGN_HOSTNAME) IGN_IP=$(IGN_IP) envsubst < templates/$(BUTANE) > $(PROJECT)/generated-butane.conf
	podman run \
		--interactive \
		--rm quay.io/coreos/butane:release \
		--pretty \
		--strict < $(PROJECT)/generated-butane.conf > /home/$(USER)/.config/libvirt/ignition/$(PROJECT).ign


# Creates and launches the VM
launch: fail-if-vm-exists ignite
	@IGNITION_DEVICE_ARG=--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=$(IGNITION_PATH)"; \
	sudo virt-install --connect="qemu:///system" --autoconsole none \
        --hvm \
        --name="${VM_NAME}" --vcpus="${VCPUS}" --memory="${RAM_MB}" \
        --os-variant="fedora-coreos-$(STREAM)" --import --graphics=none \
        --disk="size=${DISK_GB},backing_store=${IMAGE}" \
        --network network=bridged-network "$${IGNITION_DEVICE_ARG[@]}"

# Forcibly stops the VM
destroy:
	@sudo virsh destroy $(VM_NAME)


# Stops the VM
shutdown:
	@sudo virsh shutdown $(VM_NAME) || echo Already shutdown


# Shutdown the VM then delete it.
delete: shutdown
	@sleep 5
	@sudo virsh undefine $(VM_NAME) --remove-all-storage --nvram


# SSH into the VM. No hostkey checking since replacing the VM often will trigger errors anyway.
ssh:
	ssh -o "StrictHostKeyChecking=no" core@$(IGN_IP)


# Removes the downloaded CoreOS files
clean-download:
	rm -f coreos.qcow2.xz coreos.qcow2 coreos.qcow2.version

# Downloads the CoreOS qcow2 VM disk, extracts it and verifies the SHA256 hash.
coreos.qcow2:
	# Get JSON
	@$(eval CURRENT_RELEASE := $(shell curl -s https://builds.coreos.fedoraproject.org/streams/$(STREAM).json | jq -r '.architectures.x86_64.artifacts.qemu.release'))
	#@wget https://builds.coreos.fedoraproject.org/prod/streams/$(STREAM)/builds/$(CURRENT_RELEASE)/x86_64/fedora-coreos-$(CURRENT_RELEASE)-qemu.x86_64.qcow2.xz -O coreos.qcow2.xz
	@$(eval SHA := $(shell curl -s https://builds.coreos.fedoraproject.org/streams/$(STREAM).json | jq -r '.architectures.x86_64.artifacts.qemu.formats["qcow2.xz"].disk.sha256'))
	@echo $(SHA) coreos.qcow2.xz | sha256sum -c
	@echo $(CURRENT_RELEASE) > coreos.qcow2.version
	@xz --decompress coreos.qcow2.xz

# Alias
clean: clean-ignite

# Alias
download: coreos.qcow2