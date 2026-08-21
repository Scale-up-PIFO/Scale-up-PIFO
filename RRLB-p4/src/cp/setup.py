import socket
import sys
import os
import time
import math

hostname = socket.gethostname()
print("Hostname: {}".format(hostname))

l2_forward_configs=[
    (0x7F000001,132)
]

# Current scaleup.p4 uses a range table for rank -> counter index.
# These are left endpoints. The first range must start at rank 0, and the
# final configured range is extended through the maximum 16-bit rank.
rank_borders = [0, 5, 10, 15, 20, 25, 30, 40, 50]
counter_init_values = [0 for _ in range(16)]

if "PIFO_RANK_BORDERS" in os.environ:
    rank_borders = [int(v) for v in os.environ["PIFO_RANK_BORDERS"].split(",")]
if "PIFO_COUNTER_INIT" in os.environ:
    counter_init_values = [int(v) for v in os.environ["PIFO_COUNTER_INIT"].split(",")]

if not 1 <= len(rank_borders) <= 16:
    raise ValueError("PIFO_RANK_BORDERS must contain between 1 and 16 comma-separated values")
if rank_borders[0] != 0:
    raise ValueError("PIFO_RANK_BORDERS must start at 0")
if any(left >= right for left, right in zip(rank_borders, rank_borders[1:])):
    raise ValueError("PIFO_RANK_BORDERS must be strictly increasing")
if rank_borders[-1] > 65535:
    raise ValueError("PIFO_RANK_BORDERS values must not exceed 65535")
if len(counter_init_values) != 16:
    raise ValueError("PIFO_COUNTER_INIT must contain exactly 16 comma-separated values")

if hostname == 'P4-2':
    fp_port_configs = [
                    ('1/0', '100G', 'NONE', 2),    
                    ('2/0', '100G', 'NONE', 2), 
                    # more config with your topology
                    ]
    l2_forward_configs=[
                    (0x7F000001,132)
                        ]




def add_port_config(port_config):
    speed_dict = {'10G':'BF_SPEED_10G', '25G':'BF_SPEED_25G', '40G':'BF_SPEED_40G', '100G':'BF_SPEED_100G'}
    fec_dict = {'NONE':'BF_FEC_TYP_NONE', 'FC':'BF_FEC_TYP_FC', 'RS':'BF_FEC_TYP_RS'}
    an_dict = {0:'PM_AN_DEFAULT', 1:'PM_AN_FORCE_ENABLE', 2:'PM_AN_FORCE_DISABLE'}
    lanes_dict = {'10G':(0,1,2,3), '25G':(0,1,2,3), '40G':(0,), '50G':(0,2), '100G':(0,)}
    
    # extract and map values from the config first
    conf_port = int(port_config[0].split('/')[0])
    lane = port_config[0].split('/')[1]
    conf_speed = speed_dict[port_config[1]]
    conf_fec = fec_dict[port_config[2]]
    conf_an = an_dict[port_config[3]]


    if lane == '-': # need to add all possible lanes
        lanes = lanes_dict[port_config[1]]
        for lane in lanes:
            dp = bfrt.port.port_hdl_info.get(CONN_ID=conf_port, CHNL_ID=lane, print_ents=False).data[b'$DEV_PORT']
            bfrt.port.port.add(DEV_PORT=dp, SPEED=conf_speed, FEC=conf_fec, AUTO_NEGOTIATION=conf_an, PORT_ENABLE=True)
    else: # specific lane is requested
        conf_lane = int(lane)
        dp = bfrt.port.port_hdl_info.get(CONN_ID=conf_port, CHNL_ID=conf_lane, print_ents=False).data[b'$DEV_PORT']
        bfrt.port.port.add(DEV_PORT=dp, SPEED=conf_speed, FEC=conf_fec, AUTO_NEGOTIATION=conf_an, PORT_ENABLE=True)



def set_forward_table(l2_forward_configs):
    table = bfrt.scaleup.pipe.SwitchIngress.forward_table
    for l2_forward_config in l2_forward_configs:
        table.add_with_ipv4_forward(*l2_forward_config)

def set_reg_val():
    ingress = bfrt.scaleup.pipe.SwitchIngress
    for index in range(16):
        ingress.counters.mod(index, counter_init_values[index])
    # ingress.port_counter_4.mod(0,1);
    # ingress.port_counter_5.mod(0,1);
    # ingress.port_counter_6.mod(0,1);
    # ingress.port_counter_7.mod(0,1);

def add_rank_range_entry(table, start, end, index, priority):
    attempts = [
        lambda: table.add_with_set_counter_index(start, end, index),
        lambda: table.add_with_set_counter_index(start, end, index, priority),
        lambda: table.add_with_set_counter_index(priority, start, end, index),
        lambda: table.add_with_set_counter_index((start, end), index),
        lambda: table.add_with_set_counter_index((start, end), index, priority),
        lambda: table.add_with_set_counter_index(priority, (start, end), index),
    ]
    last_error = None
    for attempt in attempts:
        try:
            attempt()
            return
        except Exception as e:
            last_error = e
    raise last_error

def set_rank_to_counter_table():
    table = bfrt.scaleup.pipe.SwitchIngress.rank_to_counter_table
    priority = 1000
    for index, start in enumerate(rank_borders):
        if index + 1 < len(rank_borders):
            end = rank_borders[index + 1] - 1
        else:
            end = 65535

        add_rank_range_entry(table, start, end, index, priority)
        priority -= 1



if hostname == 'P4-2':
    for port_config in fp_port_configs:
        add_port_config(port_config)

set_reg_val()
set_rank_to_counter_table()
set_forward_table(l2_forward_configs)


print('setup over')
