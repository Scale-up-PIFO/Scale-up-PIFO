#include "IdealPIFOScheduler.h"

namespace ns3 {

NS_OBJECT_ENSURE_REGISTERED(IdealPIFOScheduler);

TypeId
IdealPIFOScheduler::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::IdealPIFOScheduler")
        .SetParent<QueueDisc>()
        .SetGroupName("TrafficControl")
        .AddConstructor<IdealPIFOScheduler>();
    return tid;
}

void IdealPIFOScheduler::InitializeParams(void) {

}

IdealPIFOScheduler::Pkt::Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size)
    : pktid(pktid), flowid(flowid), length(length), flow_size(flow_size) {}

    IdealPIFOScheduler::PifoItem::PifoItem(double rank, double sendPacketTime, Pkt pkt)
    : rank(rank), sendPacketTime(sendPacketTime), pkt(pkt) {}

bool IdealPIFOScheduler::PifoItem::operator<(const PifoItem& other) const {
    if (rank != other.rank) {
        return rank < other.rank;
    } else {
        return sendPacketTime < other.sendPacketTime;
    }
}

IdealPIFOScheduler::IdealPIFOScheduler()
    : m_pifoSize(0.0) {}

int IdealPIFOScheduler::GetFlowLabel(Ptr<QueueDiscItem> item) {
    Ptr<const Ipv4QueueDiscItem> ipItem = DynamicCast<const Ipv4QueueDiscItem>(item);
    if (!ipItem) {
        return -1;
    }

    Ptr<const Packet> packet = ipItem->GetPacket();
    Ipv4Header ipv4Header;

    packet->PeekHeader(ipv4Header);

    uint8_t protocol = ipv4Header.GetProtocol();
    uint16_t sourcePort = 0;
    uint16_t destPort = 0;

    if (protocol == 6) {
        TcpHeader tcpHeader;

        packet->PeekHeader(tcpHeader);
        sourcePort = tcpHeader.GetSourcePort();
        destPort = tcpHeader.GetDestinationPort();
    } else if (protocol == 17) {
        UdpHeader udpHeader;

        packet->PeekHeader(udpHeader);
        sourcePort = udpHeader.GetSourcePort();
        destPort = udpHeader.GetDestinationPort();
    } else {

        return -1;
    }

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

double IdealPIFOScheduler::RankCal(Pkt pkt) {

    return pkt.flow_size;
}

void IdealPIFOScheduler::Drop(Ptr<QueueDiscItem> item) {

    QueueDisc::Drop(item);
}

bool IdealPIFOScheduler::DoEnqueue(Ptr<QueueDiscItem> item) {
    Ptr<Packet> packet = GetPointer(item->GetPacket());
    TenantTag my_tag;
    packet->PeekPacketTag(my_tag);
    int flow_size = my_tag.GetTenantId();
    if (flow_size == 100000001) {
        flow_size = 1;
    }

    Timestamptag ts;
    double sendTime = 0.0;
    if (packet->PeekPacketTag(ts)) {
        sendTime = ts.GetTimestamp().GetNanoSeconds();
    }

    int packet_size = packet->GetSize();
    int flow_id = GetFlowLabel(item);

    Pkt pkt(item, flow_id, packet_size, flow_size);
    double rank = RankCal(pkt);

    PifoItem pifoItem(rank, sendTime, pkt);

    while (m_pifoSize + packet_size > m_bufferSize) {
        if (m_queue.empty()) {

            Drop(item);
            return false;
        }

        auto tail_it = std::prev(m_queue.end());
        PifoItem tail_element = *tail_it;

        m_queue.erase(tail_it);
        m_pifoSize -= tail_element.pkt.length;

        Drop(tail_element.pkt.pktid);
    }

    m_queue.insert(pifoItem);
    m_pifoSize += packet_size;

    return true;
}

Ptr<QueueDiscItem> IdealPIFOScheduler::DoDequeue() {
    if (m_queue.empty()) {
        return nullptr;
    }

    auto head_it = m_queue.begin();
    PifoItem element = *head_it;

    m_queue.erase(head_it);
    m_pifoSize -= element.pkt.length;

    return element.pkt.pktid;
}

Ptr<const QueueDiscItem> IdealPIFOScheduler::DoPeek(void) const {

    return 0;
}

bool IdealPIFOScheduler::CheckConfig(void) {

    return true;
}

}
