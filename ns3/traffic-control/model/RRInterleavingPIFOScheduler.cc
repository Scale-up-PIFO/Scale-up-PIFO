#include "RRInterleavingPIFOScheduler.h"

namespace ns3 {

NS_OBJECT_ENSURE_REGISTERED(RRInterleavingPIFOScheduler);

TypeId
RRInterleavingPIFOScheduler::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::RRInterleavingPIFOScheduler")
        .SetParent<QueueDisc>()
        .SetGroupName("TrafficControl")
        .AddConstructor<RRInterleavingPIFOScheduler>();
    return tid;
}

RRInterleavingPIFOScheduler::Pkt::Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size)
    : pktid(pktid), flowid(flowid), length(length), flow_size(flow_size) {}

bool RRInterleavingPIFOScheduler::PifoItem::operator<(const PifoItem& other) const {
     if (rank != other.rank) {
        return rank < other.rank;
    } else {
        return sendPacketTime < other.sendPacketTime;
    }
}

RRInterleavingPIFOScheduler::PifoItem::PifoItem(double rank, double sendPacketTime, Pkt pkt)
    : rank(rank), sendPacketTime(sendPacketTime), pkt(pkt) {}

RRInterleavingPIFOScheduler::RRInterleavingPIFOScheduler()
    : m_inputPointer(0),
      m_outputPointer(0),
      m_ackInputPointer(0),
      m_ackOutputPointer(0) {}

void RRInterleavingPIFOScheduler::InitializeParams(void) {
    m_bufferPerPifo = BUFFER_SIZE / PIFO_NUM;

    m_queues.assign(PIFO_NUM, std::multiset<PifoItem>());
    m_pifoSizes.assign(PIFO_NUM, 0.0);
}

int RRInterleavingPIFOScheduler::GetFlowLabel(Ptr<QueueDiscItem> item) {
    Ptr<const Ipv4QueueDiscItem> ipItem = DynamicCast<const Ipv4QueueDiscItem>(item);
    if (!ipItem) {
        return -1;
    }

    Ptr<const Packet> packet = ipItem->GetPacket();
    Ipv4Header ipv4Header;

    packet->PeekHeader(ipv4Header);

    uint16_t sourcePort = 0;
    uint16_t destPort = 0;

    UdpHeader udpHeader;

    packet->PeekHeader(udpHeader);
    sourcePort = udpHeader.GetSourcePort();
    destPort = udpHeader.GetDestinationPort();

    int flowId = 65535;
    if (sourcePort < 30000) {
        flowId = sourcePort;
    } else if (destPort < 30000) {
        flowId = destPort;
    }

    if (flowId == 65535) {
        flowId = 1001;
    }

    return flowId;
}

double RRInterleavingPIFOScheduler::RankCal(Pkt pkt) {

    return pkt.flow_size;
}

void RRInterleavingPIFOScheduler::Drop(Ptr<QueueDiscItem> item) {
    QueueDisc::Drop(item);
}

bool RRInterleavingPIFOScheduler::DoEnqueue(Ptr<QueueDiscItem> item) {
    Ptr<Packet> packet = GetPointer(item->GetPacket());
    TenantTag my_tag;
    packet->PeekPacketTag(my_tag);
    int flow_size = my_tag.GetTenantId();

    int packet_size = packet->GetSize();
    if (flow_size == 100000001) {
        flow_size = 1;

        int queue_index = m_ackInputPointer % PIFO_NUM;
        m_pifoSizes[queue_index] += packet_size;
        m_ackInputPointer++;

        m_ackFifo.push_back(item);
        return true;
    }
    Timestamptag ts;
    double sendTime = 0.0;
    if (packet->PeekPacketTag(ts)) {
        sendTime = ts.GetTimestamp().GetNanoSeconds();

    }

    int flow_id = GetFlowLabel(item);

    int queue_index = m_inputPointer % PIFO_NUM;
    std::multiset<PifoItem>& current_queue = m_queues[queue_index];

    double required_size = m_pifoSizes[queue_index] + packet_size;

    while (required_size > m_bufferPerPifo && !current_queue.empty()) {

        auto it = std::prev(current_queue.end());
        PifoItem removed_item = *it;

        Drop(removed_item.pkt.pktid);

        current_queue.erase(it);
        m_pifoSizes[queue_index] -= removed_item.pkt.length;
        required_size = m_pifoSizes[queue_index] + packet_size;
    }

    if (required_size > m_bufferPerPifo) {
        Drop(item);
        return false;
    }

    Pkt pkt(item, flow_id, packet_size, flow_size);
    double rank = RankCal(pkt);
    PifoItem pifoItem(rank,sendTime, pkt);
    current_queue.insert(pifoItem);
    m_pifoSizes[queue_index] += packet_size;
    m_inputPointer++;

    return true;
}

Ptr<QueueDiscItem> RRInterleavingPIFOScheduler::DoDequeue() {

    if (!m_ackFifo.empty()) {

        Ptr<QueueDiscItem> ack_item = m_ackFifo.front();
        m_ackFifo.pop_front();

        int packet_size = ack_item->GetPacket()->GetSize();
        int queue_index = m_ackOutputPointer % PIFO_NUM;
        m_pifoSizes[queue_index] -= packet_size;
        m_ackOutputPointer++;

        return ack_item;
    }

    for (int i = 0; i < PIFO_NUM; ++i) {
        int queue_index = m_outputPointer % PIFO_NUM;
        std::multiset<PifoItem>& current_queue = m_queues[queue_index];

        if (!current_queue.empty()) {

            auto it = current_queue.begin();
            PifoItem element = *it;
            current_queue.erase(it);

            m_pifoSizes[queue_index] -= element.pkt.length;

            m_outputPointer++;

            return element.pkt.pktid;
        } else {

            m_outputPointer++;
        }
    }

    return nullptr;
}

Ptr<const QueueDiscItem> RRInterleavingPIFOScheduler::DoPeek(void) const {

    return nullptr;
}

bool RRInterleavingPIFOScheduler::CheckConfig(void) {
    return true;
}

}
