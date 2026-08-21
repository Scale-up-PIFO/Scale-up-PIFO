#include "SPPIFOScheduler.h"

namespace ns3 {

NS_OBJECT_ENSURE_REGISTERED(SPPIFOScheduler);

SPPIFOScheduler::Pkt::Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size)
    : pktid(pktid), flowid(flowid), length(length), flow_size(flow_size) {}

SPPIFOScheduler::PifoItem::PifoItem(double rank, Pkt pkt)
    : rank(rank), pkt(pkt) {}

TypeId SPPIFOScheduler::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::SPPIFOScheduler")
        .SetParent<QueueDisc>()
        .SetGroupName("TrafficControl")
        .AddConstructor<SPPIFOScheduler>()
        .AddAttribute("FifoNum", "Number of FIFOs.",
                      UintegerValue(8), MakeUintegerAccessor(&SPPIFOScheduler::m_fifoNum),
                      MakeUintegerChecker<int>(1, 100))
        .AddAttribute("BufferSize", "Total buffer size.",
                      DoubleValue(5 * 1024 * 1024), MakeDoubleAccessor(&SPPIFOScheduler::m_bufferSize),
                      MakeDoubleChecker<double>());
    return tid;
}

SPPIFOScheduler::SPPIFOScheduler() {}

void SPPIFOScheduler::InitializeParams(void) {
    m_perFifoBuffer = m_bufferSize / m_fifoNum;
    m_borders.assign(m_fifoNum, 0.0);
    m_fifoSizes.assign(m_fifoNum, 0.0);
    m_fifos.assign(m_fifoNum, std::deque<PifoItem>());
}

int SPPIFOScheduler::GetFlowLabel(Ptr<QueueDiscItem> item) {
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

double SPPIFOScheduler::RankCal(Pkt pkt) {

    return pkt.flow_size;
}

void SPPIFOScheduler::Drop(Ptr<QueueDiscItem> item) {
    QueueDisc::Drop(item);
}

bool SPPIFOScheduler::DoEnqueue(Ptr<QueueDiscItem> item) {
    Ptr<Packet> packet = GetPointer(item->GetPacket());
    TenantTag my_tag;
    packet->PeekPacketTag(my_tag);
    int flow_size = my_tag.GetTenantId();
    if (flow_size == 100000001) {
        flow_size = 1;
    }
    int packet_size = packet->GetSize();
    int flow_id = GetFlowLabel(item);

    Pkt pkt(item, flow_id, packet_size, flow_size);
    double rank = RankCal(pkt);
    PifoItem element(rank, pkt);

    bool inserted = false;

    for (int i = 0; i < m_fifoNum; ++i) {

        if (rank >= m_borders[i]) {

            if ((m_fifoSizes[i] + pkt.length) <= m_perFifoBuffer) {

                if (m_fifos[i].empty() || rank > m_borders[i]) {
                     m_borders[i] = rank;
                }
                m_fifos[i].push_back(element);
                m_fifoSizes[i] += pkt.length;
                inserted = true;
                break;
            } else {

                Drop(item);
                return false;
            }
        }
    }

    if (!inserted) {

        double delta = m_borders[0] - rank;
        for (int i = 0; i < m_fifoNum; ++i) {
            m_borders[i] -= delta;
        }

        if ((m_fifoSizes[0] + pkt.length) <= m_perFifoBuffer) {
            m_fifos[0].push_back(element);
            m_fifoSizes[0] += pkt.length;
            return true;
        } else {

            Drop(item);
            return false;
        }
    }

    return inserted;
}

Ptr<QueueDiscItem> SPPIFOScheduler::DoDequeue() {

    for (int i = 0; i < m_fifoNum; ++i) {
        if (!m_fifos[i].empty()) {
            PifoItem element = m_fifos[i].front();
            m_fifos[i].pop_front();
            m_fifoSizes[i] -= element.pkt.length;
            return element.pkt.pktid;
        }
    }
    return nullptr;
}

Ptr<const QueueDiscItem> SPPIFOScheduler::DoPeek(void) const {
    for (int i = 0; i < m_fifoNum; ++i) {
        if (!m_fifos[i].empty()) {
            return m_fifos[i].front().pkt.pktid;
        }
    }
    return nullptr;
}

bool SPPIFOScheduler::CheckConfig(void) {
    return true;
}

}
