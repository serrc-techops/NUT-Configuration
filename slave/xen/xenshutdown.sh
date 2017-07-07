#!/bin/bash
# Shutdown all running VMs in a Xen pool
#
# This script will only run on the pool master
#
# version 1.0

main () {

	# Seconds until VM clean shutdown times out (seconds until force shutdown initiated)
	shutdown_timeout=600

	# Seconds until VM force shutdown times out (seconds until power reset initiated)
	forcedown_timeout=60

	# Seconds to wait after initiating power reset on VM
	powerreset_timeout=60

	# Seconds until slave host shutdown timeout (seconds until master gives up and shuts itself down)
	slavehost_timeout=240

	# Log file location
	log_file="/var/log/nut.log"

	log_date "==============================================================================="
	log_date "Powerdown event recieved from NUT master, initiating shutdown proceedure"
	log_date "==============================================================================="

	# Get UUIDs of all running VMs
	vm_uuids=( $(xe vm-list power-state=running is-control-domain=false --minimal | tr , "\n" ) )

	# Shutdown each VM
	for vm_uuid in "${vm_uuids[@]}"; do
		vm_name=$(xe vm-param-get uuid=$vm_uuid param-name=name-label)
		log_date "Shutting down VM $vm_name (UUID: $vm_uuid)"
		xe vm-shutdown uuid=$vm_uuid &
		sleep 1
	done

	# Start timer for timeout
	start_time=$SECONDS

	# Loop until all VMs shutdown or timeout
	sleep 10
	while [ $(( SECONDS - start_time )) -lt $shutdown_timeout ]; do
		vm_uuids=( $(xe vm-list power-state=running is-control-domain=false --minimal | tr , "\n" ) )
		if [ ${#vm_uuids[@]} -eq 0 ]; then
			# If all VMs shutdown, shutdown hosts
			shutdown_hosts
			exit
		else
			log_date "Not all VMs shutdown, continuing to wait..."
			sleep 10
		fi
	done

	# Attempt to force shutdown any VMs still running
	vm_uuids=( $(xe vm-list power-state=running is-control-domain=false --minimal | tr , "\n" ) )
	for vm_uuid in "${vm_uuids[@]}"; do
		vm_name=$(xe vm-param-get uuid=$vm_uuid param-name=name-label)
		log_date "Shutdown timeout, attempting to force down VM $vm_name (UUID: $vm_uuid)"
		xe vm-shutdown uuid=$vm_uuid force=true &
		sleep 1
	done
	sleep $forcedown_timeout

	# Initiate power reset on any VMs still running
	vm_uuids=( $(xe vm-list power-state=running is-control-domain=false --minimal | tr , "\n" ) )
	for vm_uuid in "${vm_uuids[@]}"; do
		vm_name=$(xe vm-param-get uuid=$vm_uuid param-name=name-label)
		log_date "VM $vm_name (UUID: $vm_uuid) is still running, initiating power reset"
		xe vm-reset-powerstate uuid=$vm_uuid force=true &
		sleep 1
	done
	sleep $powerreset_timeout 

	# Procede with shutting down hosts
	shutdown_hosts

	exit	
}

shutdown_hosts () {
	# Get UUID of all hosts
	host_uuids=( $(xe host-list --minimal | tr , "\n" ) )


	# Get UUID of this host (master)
	master_uuid=$( cat /etc/xensource-inventory | grep -i installation_uuid | awk -F"'[[:blank:]]*" '{print $2}' )

	# Get UUID of slave hosts
	slave_uuids=()
	for uuid in ${host_uuids[@]}; do
		if [[ $uuid != $master_uuid ]]; then
			slave_uuids+=($uuid)
		fi
	done

	# Shutdown all slave hosts
	for uuid in ${slave_uuids[@]}; do
		host_name=$(xe host-param-get uuid=$uuid param-name=name-label)
		log_date "Disabling slave host $uuid (UUID: $uuid)"
		xe host-disable uuid=$uuid
		sleep 1
		log_date "Shutting down slave host $host_name (UUID: $uuid)"
		xe host-shutdown uuid=$uuid &
		sleep 1
	done

	# Start timer for timeout
	start_time=$SECONDS

	# Loop until all slave hosts do not respond to ping or timeout
	sleep 10
	for uuid in ${slave_uuids[@]}; do
		if [ $(( SECONDS - start_time )) -lt $slavehost_timeout ]; then
			while true; do
				ping -c 1 $(xe host-param-get uuid=$uuid param-name=address) > /dev/null 2> /dev/null
				# If slave replies to ping
				if [ $? -eq 0 ]; then
					log_date "Not all slave hosts shutdown, continuing to wait..."
					sleep 10
					continue
				else
					sleep 2
					break
				fi
			done
		else
			log_date "Slave host shutdown timeout, proceeding with master host shutdown"
		fi
	done

	# Shutdown master host
	master_name=$(xe host-param-get uuid=$master_uuid param-name=name-label)
	log_date "Disabling master host $master_name (UUID: $master_uuid)"
	xe host-disable uuid=$master_uuid
	sleep 1
	log_date "Shutting down master host $master_name (UUID: $master_uuid)"
	xe host-shutdown uuid=$master_uuid
	sleep 1
}

log_date () {
	# logging function formatted to include a date
	echo -e "$(date "+%Y/%m/%d %H:%M:%S"): $1" > "$log_file" #2>&1
	echo -e "$1"
}

# Check that host has master role
role=$(more /etc/xensource/pool.conf)
if [ $role = "master" ]; then
	main
fi
