#!/usr/bin/env bash

# mesh_retry_timeout = 100 milliseconds
# mesh_confirm_timeout = 100 milliseconds
# mesh_holding_timeout = 100 milliseconds
# mesh_max_peer_links = 99
# mesh_max_retries = 3
# mesh_ttl = 31
# mesh_element_ttl = 31
# mesh_auto_open_plinks = 0
# mesh_hwmp_max_preq_retries = 4
# mesh_path_refresh_time = 1000 milliseconds
# mesh_min_discovery_timeout = 100 milliseconds
# mesh_hwmp_active_path_timeout = 5000 TUs
# mesh_hwmp_preq_min_interval = 10 TUs
# mesh_hwmp_net_diameter_traversal_time = 50 TUs
# mesh_hwmp_rootmode = 0
# mesh_hwmp_rann_interval = 5000 TUs
# mesh_gate_announcements = 0
# mesh_fwding = 1
# mesh_sync_offset_max_neighor = 50
# mesh_rssi_threshold = 0 dBm
# mesh_hwmp_active_path_to_root_timeout = 6000 TUs
# mesh_hwmp_root_interval = 5000 TUs
# mesh_hwmp_confirmation_interval = 2000 TUs
# mesh_power_mode = active
# mesh_awake_window = 10 TUs
# mesh_plink_timeout = 0 seconds
# mesh_connected_to_gate = 0
# mesh_nolearn = 0
# mesh_connected_to_as = 0

# Here is a list of available parameters and their function:
#
#     mesh_retry_timeout: the initial retry timeout in millisecond units used by the Mesh Peering Open message
#
#     mesh_confirm_timeout: the initial confirm timeout in millisecond units used by the Mesh Peering Open message
#
#     mesh_holding_timeout: the confirm timeout in millisecond units used by the mesh peering management to close a mesh peering
#
#     mesh_max_peer_links: the maximum number of peer links allowed on this mesh interface
#
#     mesh_max_retries: the maximum number of peer link open retries that can be sent to establish a new peer link instance in a mesh
#
#     mesh_ttl: the value of TTL field set at a source mesh STA (STAtion)
#
#     mesh_element_ttl: the value of TTL field set at a mesh STA for path selection elements
#
#     mesh_auto_open_plinks: whether peer links should be automatically opened when compatible mesh peers are detected [deprecated - most implementations hard coded to enabled]
#
#     mesh_sync_offset_max_neighor: (note the odd spelling)- the maximum number of neighbors to synchronize to
#
#     mesh_hwmp_max_preq_retries: the number of action frames containing a PREQ (PeerREQuest) that an originator mesh STA can send to a particular path target
#
#     mesh_path_refresh_time: how frequently to refresh mesh paths in milliseconds
#
#     mesh_min_discovery_timeout: the minimum length of time to wait until giving up on a path discovery in milliseconds
#
#     mesh_hwmp_active_path_timeout: the time in milliseconds for which mesh STAs receiving a PREQ shall consider the forwarding information from the root to be valid.
#
#     mesh_hwmp_preq_min_interval: the minimum interval of time in milliseconds during which a mesh STA can send only one action frame containing a PREQ element
#
#     mesh_hwmp_net_diameter_traversal_time: the interval of time in milliseconds that it takes for an HWMP (Hybrid Wireless Mesh Protocol) information element to propagate across the mesh
#
#     mesh_hwmp_rootmode: the configuration of a mesh STA as root mesh STA
#
#     mesh_hwmp_rann_interval: the interval of time in milliseconds between root announcements (rann - RootANNouncement)
#
#     mesh_gate_announcements: whether to advertise that this mesh station has access to a broader network beyond the MBSS (Mesh Basic Service Set, a self-contained network of mesh stations that share a mesh profile)
#
#     mesh_fwding: whether the Mesh STA is forwarding or non-forwarding
#
#     mesh_rssi_threshold: the threshold for average signal strength of candidate station to establish a peer link
#
#     mesh_hwmp_active_path_to_root_timeout: The time in milliseconds for which mesh STAs receiving a proactive PREQ shall consider the forwarding information to the root mesh STA to be valid
#
#     mesh_hwmp_root_interval: The interval of time in milliseconds between proactive PREQs
#
#     mesh_hwmp_confirmation_interval: The minimum interval of time in milliseconds during which a mesh STA can send only one Action frame containing a PREQ element for root path confirmation
#
#     mesh_power_mode: The default mesh power save mode which will be the initial setting for new peer links
#
#     mesh_awake_window: The duration in milliseconds the STA will remain awake after transmitting its beacon
#
#     mesh_plink_timeout: If no tx activity is seen from a peered STA for longer than this time (in seconds), then remove it from the STA's list of peers. Default is 0, equating to 30 minutes
#
#     mesh_connected_to_as: if set to true then this mesh STA will advertise in the mesh station information field that it is connected to a captive portal authentication server, or in the simplest case, an upstream router
#
#     mesh_connected_to_gate: if set to true then this mesh STA will advertise in the mesh station information field that it is connected to a separate network infrastucture such as a wireless network or downstream router
#
#     mesh_nolearn: Try to avoid multi-hop path discovery if the destination is a direct neighbour. Note that this will not be optimal as multi-hop mac-routes will not be discovered. If using this setting, disable mesh forwarding and use another mesh routing protocol
#
#
