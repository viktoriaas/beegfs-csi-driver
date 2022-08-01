# Copyright 2022 NetApp, Inc. All Rights Reserved.
# Licensed under the Apache License, Version 2.0.

# Browse the full set of configuration options at https://www.nomadproject.io/docs/job-specification.

job "beegfs-csi-plugin-node" {
  # Job type system is analogous to a Kubernetes DaemonSet (runs on all nodes, restarts indefinitely). See other 
  # options at https://www.nomadproject.io/docs/schedulers.
  type = "system"

  # LIKELY TO REQUIRE MODIFICATION.
  # "dc1" is a default for basic deployments, but this depends on the environment.
  datacenters = ["dc1"]

  # A group is analagous to a Kubernetes Pod.
  group "node" {
    task "node" {
      # This plugin has only been tested with the docker driver. It may be possible to support the podman driver in the 
      # future. 
      driver = "docker"

      config {
        image = "docker.repo.eng.netapp.com/globalcicd/apheleia/beegfs-csi-driver:master"

        # chwrap is used to execute the beegfs-ctl binary already installed on the host. We also read the 
        # beegfs-client.conf template already installed on the host.
        # The host filesystem is mounted at: /host.
        mount {
          type     = "bind"
          target   = "/host"
          source   = "/"
          readonly = true
          bind_options {
            # Because we chwrap mount/umount, we must propagate the container's /host mounts to the node.
            propagation = "rshared"
          }
        }

        args = [
          "--driver-name=beegfs.csi.netapp.com",
          "--client-conf-template-path=/host/etc/beegfs/beegfs-client.conf",
          "--config-path=${NOMAD_TASK_DIR}/csi-beegfs-config.yaml",
          "--connauth-path=${NOMAD_SECRETS_DIR}/csi-beegfs-connauth.yaml",
          "--v=3",
          "--endpoint=${CSI_ENDPOINT}",
          "--node-id=node-${node.unique.name}"
        ]

        # We must run with privileges in order to mount volumes.
        privileged = true
      }

      csi_plugin {
        # Specific to Nomad. Some important paths include this field.
        id = "beegfs-csi-plugin"
        type = "node"

        # The BeeGFS CSI driver must be instructed to stage and publish volumes in a directory with the same path 
        # inside and outside of its container. Nomad always facilitates staging and publishing in the 
        # /opt/nomad/client/... directory as seen outside the container, but by default it represents this directory 
        # inside the container as /local/csi. This usage of the stage_publish_dir field ensures the driver operates 
        # correctly. Note that the final component of the path must match csi_plugin.id. Note that the final component 
        # of this path must match csi_plugin.id. 
        # NOTE: This will not work until https://github.com/hashicorp/nomad/issues/13263 is resolved.
        stage_publish_dir = "/opt/nomad/client/csi/node/beegfs-csi-plugin"
      }

      resources {
        cpu = 256
        memory = 128
      }
      
      # LIKELY TO REQUIRE MODIFICATION.
      # csi-beegfs-config.yaml is the primary means of configuring the BeeGFS CSI driver. See 
      # https://github.com/NetApp/beegfs-csi-driver/blob/master/docs/deployment.md#managing-beegfs-client-configuration 
      # for details.
      # This stanza must be kept in sync with its partner in controller.nomad.
      template {
        data        = <<EOH
config:
  # Test file systems are intentionally misconfigured to first advertise an interface/address that is unreachable. This 
  # connNetFilter configuration overcomes that misconfiguration and speeds up mounting for test cases that don't make 
  # use of it.
  beegfsClientConf:
    connUseRDMA: "false"
  connNetFilter:
    - 10.113.4.0/24
fileSystemSpecificConfigs:
  - sysMgmtdHost: 10.113.4.71
  - sysMgmtdHost: 10.113.4.72
    config:
      beegfsClientConf:
        connMgmtdPortTCP: "9009"
        connMgmtdPortUDP: "9009"
EOH
        destination = "${NOMAD_TASK_DIR}/csi-beegfs-config.yaml"
      }

      # LIKELY TO REQUIRE MODIFICATION.
      # csi-beegfs-connauth.yaml container connauth information required by the BeeGFS client to mount secured file 
      # systems. See https://github.com/NetApp/beegfs-csi-driver/blob/master/docs/deployment.md#connauth-configuration 
      # for details.
      # This stanza must be kept in sync with its partner in controller.nomad.
      template {
        data        = <<EOH
- sysMgmtdHost: 10.113.4.72
  connAuth: secret1
EOH
        destination = "${NOMAD_SECRETS_DIR}/csi-beegfs-connauth.yaml"
      }
    }
  }
}
