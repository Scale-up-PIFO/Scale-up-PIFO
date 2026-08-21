#include "AIFOScheduler.h"

namespace ns3 {

NS_OBJECT_ENSURE_REGISTERED(AIFOScheduler);

AIFOScheduler::Pkt::Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size)
    : pktid(pktid), flowid(flowid), length(length), flow_size(flow_size) {}

AIFOScheduler::Element::Element(double rank, Pkt pkt)
    : rank(rank), pkt(pkt) {}

TypeId AIFOScheduler::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::AIFOScheduler")
        .SetParent<QueueDisc>()
        .SetGroupName("TrafficControl")
        .AddConstructor<AIFOScheduler>()
        .AddAttribute("WindowSize", "Sliding window size.",
                      UintegerValue(20), MakeUintegerAccessor(&AIFOScheduler::m_windowSize),
                      MakeUintegerChecker<int>())
        .AddAttribute("BufferSize", "Queue buffer size.",
                      DoubleValue(10 * 1024 * 1024), MakeDoubleAccessor(&AIFOScheduler::m_bufferSize),
                      MakeDoubleChecker<double>())
        .AddAttribute("K", "Admission control parameter.",
                      DoubleValue(0.1), MakeDoubleAccessor(&AIFOScheduler::m_k),
                      MakeDoubleChecker<double>());
    return tid;
}

AIFOScheduler::AIFOScheduler() {
    m_windowSize = 20;
    m_bufferSize = 10 * 1024 * 1024;
    m_k = 0.1;
    InitializeParams();
}

void AIFOScheduler::InitializeParams(void) {
    m_slidingWindow.assign(m_windowSize, 0.0);
    m_windowPointer = 0;
    m_currentBufferUsage = 0;
}

int AIFOScheduler::GetFlowLabel(Ptr<QueueDiscItem> item) {
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

double AIFOScheduler::RankCal(Pkt pkt) {

    return pkt.flow_size;
}

void AIFOScheduler::Drop(Ptr<QueueDiscItem> item) {
    QueueDisc::Drop(item);
}

bool AIFOScheduler::DoEnqueue(Ptr<QueueDiscItem> item) {
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
    Element element(rank, pkt);

    m_slidingWindow[m_windowPointer % m_windowSize] = rank;
    m_windowPointer++;

    int smallerCount = 0;
    for (double r : m_slidingWindow) {
        if (r < rank) {
            smallerCount++;
        }
    }
    double quantile = static_cast<double>(smallerCount) / m_windowSize;

    double c = m_currentBufferUsage;

    if (c < m_k * m_bufferSize) {

        if (m_currentBufferUsage + pkt.length <= m_bufferSize) {
            m_fifoQueue.push_back(element);
            m_currentBufferUsage += pkt.length;
            return true;
        } else {
            Drop(item);
            return false;
        }
    } else {

        double threshold = (m_bufferSize - c) / (m_bufferSize * (1 - m_k));
        if (quantile < threshold) {
            if (m_currentBufferUsage + pkt.length <= m_bufferSize) {
                m_fifoQueue.push_back(element);
                m_currentBufferUsage += pkt.length;
                return true;
            } else {
                Drop(item);
                return false;
            }
        } else {
            Drop(item);
            return false;
        }
    }
}

Ptr<QueueDiscItem> AIFOScheduler::DoDequeue() {
    if (m_fifoQueue.empty()) {
        return nullptr;
    }

    Element element = m_fifoQueue.front();
    m_fifoQueue.pop_front();
    m_currentBufferUsage -= element.pkt.length;
    return element.pkt.pktid;
}

Ptr<const QueueDiscItem> AIFOScheduler::DoPeek(void) const {
    if (m_fifoQueue.empty()) {
        return nullptr;
    }
    return m_fifoQueue.front().pkt.pktid;
}

bool AIFOScheduler::CheckConfig(void) {
    return true;
}

}
