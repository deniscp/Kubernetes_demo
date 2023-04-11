Requirements
============

Required Ansible version >= 2.10

Tested working with Ansible (complete version, not core) v==2.10 and v==2.12
Tested not working with Ansible v==2.9

The playbook "kvm_provision.yaml" requires a KVM/QEMU VM provisionig j2 template tailored to your system.
The latter can be obtained starting from an already provisioned linux KVM/QEMU VM by using the libvirt command:

```
virsh dumpxml <linux_domain_name> > vm-template.xml
```
