import os
import socket

hostname = socket.gethostname()
print("Hostname: {}".format(hostname))

l2_forward_configs = [
    (0x7F000001, 132)
]

# scaleup_reg_8.p4 classifies a rank by counting how many configured left
# endpoints it reaches. Eight registers therefore require eight strictly
# increasing rank borders, with the first range starting at rank 0.
rank_borders = [0, 5, 10, 15, 20, 25, 30, 40]
bucket_counters = [0 for _ in range(8)]

if "PIFO_8REG_RANK_BORDERS" in os.environ:
    rank_borders = [int(v) for v in os.environ["PIFO_8REG_RANK_BORDERS"].split(",")]
elif "PIFO_8REG_BORDERS" in os.environ:
    # Backward-compatible alias for existing deployments.
    rank_borders = [int(v) for v in os.environ["PIFO_8REG_BORDERS"].split(",")]
if "PIFO_8REG_COUNTERS" in os.environ:
    bucket_counters = [int(v) for v in os.environ["PIFO_8REG_COUNTERS"].split(",")]

if len(rank_borders) != 8:
    raise ValueError("PIFO_8REG_RANK_BORDERS must contain exactly 8 comma-separated values")
if rank_borders[0] != 0:
    raise ValueError("PIFO_8REG_RANK_BORDERS must start at 0")
if any(left >= right for left, right in zip(rank_borders, rank_borders[1:])):
    raise ValueError("PIFO_8REG_RANK_BORDERS must be strictly increasing")
if rank_borders[-1] > 65535:
    raise ValueError("PIFO_8REG_RANK_BORDERS values must not exceed 65535")
if len(bucket_counters) != 8:
    raise ValueError("PIFO_8REG_COUNTERS must contain exactly 8 comma-separated values")

if hostname == "P4-2":
    fp_port_configs = [
        ("1/0", "100G", "NONE", 2),
        ("2/0", "100G", "NONE", 2),
    ]
    l2_forward_configs = [
        (0x7F000001, 132)
    ]


def add_port_config(port_config):
    speed_dict = {
        "10G": "BF_SPEED_10G",
        "25G": "BF_SPEED_25G",
        "40G": "BF_SPEED_40G",
        "50G": "BF_SPEED_50G",
        "100G": "BF_SPEED_100G",
    }
    fec_dict = {"NONE": "BF_FEC_TYP_NONE", "FC": "BF_FEC_TYP_FC", "RS": "BF_FEC_TYP_RS"}
    an_dict = {0: "PM_AN_DEFAULT", 1: "PM_AN_FORCE_ENABLE", 2: "PM_AN_FORCE_DISABLE"}
    lanes_dict = {
        "10G": (0, 1, 2, 3),
        "25G": (0, 1, 2, 3),
        "40G": (0,),
        "50G": (0, 2),
        "100G": (0,),
    }

    conf_port = int(port_config[0].split("/")[0])
    lane = port_config[0].split("/")[1]
    conf_speed = speed_dict[port_config[1]]
    conf_fec = fec_dict[port_config[2]]
    conf_an = an_dict[port_config[3]]

    if lane == "-":
        lanes = lanes_dict[port_config[1]]
        for lane in lanes:
            dp = bfrt.port.port_hdl_info.get(
                CONN_ID=conf_port, CHNL_ID=lane, print_ents=False
            ).data[b"$DEV_PORT"]
            bfrt.port.port.add(
                DEV_PORT=dp,
                SPEED=conf_speed,
                FEC=conf_fec,
                AUTO_NEGOTIATION=conf_an,
                PORT_ENABLE=True,
            )
    else:
        conf_lane = int(lane)
        dp = bfrt.port.port_hdl_info.get(
            CONN_ID=conf_port, CHNL_ID=conf_lane, print_ents=False
        ).data[b"$DEV_PORT"]
        bfrt.port.port.add(
            DEV_PORT=dp,
            SPEED=conf_speed,
            FEC=conf_fec,
            AUTO_NEGOTIATION=conf_an,
            PORT_ENABLE=True,
        )


def set_forward_table(configs):
    table = bfrt.scaleup_8reg.pipe.SwitchIngress.forward_table
    for config in configs:
        table.add_with_ipv4_forward(*config)


def set_bucket(bucket, border, counter):
    try:
        bucket.mod(0, border, counter)
    except Exception:
        bucket.mod(0, border=border, counter=counter)


def set_bucket_values():
    ingress = bfrt.scaleup_8reg.pipe.SwitchIngress
    for index in range(8):
        bucket = getattr(ingress, "bucket_{}".format(index))
        set_bucket(bucket, rank_borders[index], bucket_counters[index])


if hostname == "P4-2":
    for port_config in fp_port_configs:
        add_port_config(port_config)

set_bucket_values()
set_forward_table(l2_forward_configs)

print("8reg setup over")
