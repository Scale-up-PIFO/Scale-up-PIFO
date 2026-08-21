#include "DynamicIntervalRRPIFOScheduler.h"

namespace ns3 {

NS_OBJECT_ENSURE_REGISTERED(DynamicIntervalRRPIFOScheduler);

TypeId
DynamicIntervalRRPIFOScheduler::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::DynamicIntervalRRPIFOScheduler")
        .SetParent<QueueDisc>()
        .SetGroupName("TrafficControl")
        .AddConstructor<DynamicIntervalRRPIFOScheduler>();
    return tid;
}

DynamicIntervalRRPIFOScheduler::Pkt::Pkt(Ptr<QueueDiscItem> pktid, int flowid, int length, int flow_size)
    : pktid(pktid), flowid(flowid), length(length), flow_size(flow_size) {}

bool DynamicIntervalRRPIFOScheduler::PifoItem::operator<(const PifoItem& other) const {
    if (rank != other.rank) {
        return rank < other.rank;
    } else {
        return sendPacketTime < other.sendPacketTime;
    }
}

DynamicIntervalRRPIFOScheduler::PifoItem::PifoItem(double rank, double sendPacketTime, Pkt pkt)
    : rank(rank), sendPacketTime(sendPacketTime), pkt(pkt) {}

DynamicIntervalRRPIFOScheduler::DynamicIntervalRRPIFOScheduler()
    : m_numIntervals(16),
      m_intervalLength(0),
      m_fifoBufferSize(0),
      m_perFifoBufferLimit(0),
      m_loadBalancerIndex(0),
      m_dequeueLbIndex(0),
      m_pifoIndex(0),
      m_adjustCounter(0),
      m_ackInputPointer(0),
      m_ackOutputPointer(0) {}

void DynamicIntervalRRPIFOScheduler::InitializeParams(void) {
    m_intervalLength = static_cast<double>(INTERVAL_TOTAL_LENGTH) / m_numIntervals;
    m_fifoBufferSize = std::max(static_cast<double>(m_numIntervals * NUM_LOAD_BALANCERS * NUM_PIFOS * 1500), static_cast<double>(NUM_PIFOS * 3000));
    m_perFifoBufferLimit = m_fifoBufferSize / NUM_PIFOS;

    m_fifoBufferUsage.assign(NUM_PIFOS, 0.0);
    m_pifoCurrentSizes.assign(NUM_PIFOS, 0.0);
    m_sharedIntervalBorders.clear();
    for (int i = 0; i < m_numIntervals; ++i) {
        m_sharedIntervalBorders.push_back(i * m_intervalLength);
    }
    m_sharedIntervalBorders.push_back(static_cast<double>(INTERVAL_TOTAL_LENGTH));

    m_pifos.assign(NUM_PIFOS, std::multiset<PifoItem>());
    m_fifos.assign(NUM_PIFOS, std::deque<PifoItem>());
    m_borderCounts.assign(m_numIntervals, 0.0);

    m_intervalCounters = InitIntervalCountersWithPattern();

}

std::vector<std::vector<std::vector<int>>>
DynamicIntervalRRPIFOScheduler::InitIntervalCountersWithPattern() {
    std::vector<std::vector<int>> basePattern;
    basePattern.push_back(std::vector<int>(NUM_PIFOS, 0));
    for (int activeCount = 1; activeCount < NUM_PIFOS; ++activeCount) {
        std::vector<int> pattern(NUM_PIFOS, 0);
        for (int i = 0; i < activeCount; ++i) {
            pattern[i] = 1;
        }
        basePattern.push_back(pattern);
    }
    int patternLength = basePattern.size();

    std::vector<std::vector<std::vector<int>>> intervalCounters;
    for (int lbIdx = 0; lbIdx < NUM_LOAD_BALANCERS; ++lbIdx) {
        std::vector<std::vector<int>> lbCounters;
        for (int pifoIdx = 0; pifoIdx < NUM_PIFOS; ++pifoIdx) {
            std::vector<int> pifoCounters;
            for (int intervalIdx = 0; intervalIdx < m_numIntervals; ++intervalIdx) {
                pifoCounters.push_back(basePattern[intervalIdx % patternLength][pifoIdx]);
            }
            lbCounters.push_back(pifoCounters);
        }
        intervalCounters.push_back(lbCounters);
    }
    return intervalCounters;
}

int DynamicIntervalRRPIFOScheduler::GetIntervalIndex(double rank) {
    for (int i = 0; i < m_numIntervals; ++i) {
        if (m_sharedIntervalBorders[i] <= rank && rank < m_sharedIntervalBorders[i + 1]) {
            return i;
        }
    }
    m_sharedIntervalBorders[m_numIntervals] = rank;
    return m_numIntervals - 1;
}

int DynamicIntervalRRPIFOScheduler::SelectBestPifo(int lb_id, int interval_index) {
    int minCount = std::numeric_limits<int>::max();
    int bestPifo = 0;
    for (int pifo_id = 0; pifo_id < NUM_PIFOS; ++pifo_id) {
        int count = m_intervalCounters[lb_id][pifo_id][interval_index];
        if (count < minCount) {
            minCount = count;
            bestPifo = pifo_id;
        }
    }
    return bestPifo;
}

void DynamicIntervalRRPIFOScheduler::RefillFromFifo(int pifo_id) {
    for (int i = 0; i < REFILL_BATCH_SIZE; ++i) {
        if (m_fifos[pifo_id].empty()) {
            break;
        }
        PifoItem element = m_fifos[pifo_id].front();
        m_fifos[pifo_id].pop_front();
        m_pifos[pifo_id].insert(element);
        m_fifoBufferUsage[pifo_id] -= element.pkt.length;
        m_pifoCurrentSizes[pifo_id] += element.pkt.length;
    }

    while (m_pifoCurrentSizes[pifo_id] > PIFO_BUFFER_SIZE_PER_PIFO && !m_pifos[pifo_id].empty()) {

        auto it = std::prev(m_pifos[pifo_id].end());
        PifoItem removedElement = *it;

        Drop(removedElement.pkt.pktid);
        m_pifos[pifo_id].erase(it);
        m_pifoCurrentSizes[pifo_id] -= removedElement.pkt.length;
    }
}

std::vector<int> DynamicIntervalRRPIFOScheduler::CalculateCurrentCounts() {
    std::vector<int> currentCounts(m_numIntervals, 0);
    for (int lb_id = 0; lb_id < NUM_LOAD_BALANCERS; ++lb_id) {
        for (int pifo_id = 0; pifo_id < NUM_PIFOS; ++pifo_id) {
            for (int interval_idx = 0; interval_idx < m_numIntervals; ++interval_idx) {
                currentCounts[interval_idx] += m_intervalCounters[lb_id][pifo_id][interval_idx];
            }
        }
    }
    return currentCounts;
}

void DynamicIntervalRRPIFOScheduler::AdjustIntervals() {
    if (m_numIntervals < 2) {
        return;
    }

    std::vector<int> currentCounts = CalculateCurrentCounts();

    for (int lb_id = 0; lb_id < NUM_LOAD_BALANCERS; ++lb_id) {
        for (int interval_idx = 0; interval_idx < m_numIntervals; ++interval_idx) {
            std::vector<int> pifoCounts;
            for (int pifo_id = 0; pifo_id < NUM_PIFOS; ++pifo_id) {
                pifoCounts.push_back(m_intervalCounters[lb_id][pifo_id][interval_idx]);
            }
            int minCount = *std::min_element(pifoCounts.begin(), pifoCounts.end());
            for (int pifo_id = 0; pifo_id < NUM_PIFOS; ++pifo_id) {
                m_intervalCounters[lb_id][pifo_id][interval_idx] -= minCount;
            }
        }
    }

    for (int i = 0; i < m_numIntervals; ++i) {
        m_borderCounts[i] = m_borderCounts[i] * 0.5 + currentCounts[i];
    }

    double total = std::accumulate(m_borderCounts.begin(), m_borderCounts.end(), 0.0);
    if (total == 0) {

        return;
    }
    double meanCount = total / m_numIntervals;
    double maxCount = *std::max_element(m_borderCounts.begin(), m_borderCounts.end());
    double minCount = *std::min_element(m_borderCounts.begin(), m_borderCounts.end());

    if((m_sharedIntervalBorders[std::max_element(m_borderCounts.begin(), m_borderCounts.end()) - m_borderCounts.begin() + 1] - m_sharedIntervalBorders[std::max_element(m_borderCounts.begin(), m_borderCounts.end()) - m_borderCounts.begin()]) <= 2)
        {

            return;
        }

    if (!((maxCount > 100 && maxCount > 2 * meanCount && (m_sharedIntervalBorders[std::max_element(m_borderCounts.begin(), m_borderCounts.end()) - m_borderCounts.begin() + 1] - m_sharedIntervalBorders[std::max_element(m_borderCounts.begin(), m_borderCounts.end()) - m_borderCounts.begin()]) > 1) || minCount < 0.5 * meanCount)) {

        return;
    }

    int minIndex = std::min_element(m_borderCounts.begin(), m_borderCounts.end()) - m_borderCounts.begin();
    int mergeWith = -1;
    if (minIndex > 0 && minIndex < m_numIntervals - 1) {
        if (m_borderCounts[minIndex - 1] <= m_borderCounts[minIndex + 1]) {
            mergeWith = minIndex - 1;
        } else {
            mergeWith = minIndex + 1;
        }
    } else if (minIndex > 0) {
        mergeWith = minIndex - 1;
    } else if (minIndex < m_numIntervals - 1) {
        mergeWith = minIndex + 1;
    }
    if (mergeWith != -1) {
        int mergeStart = std::min(minIndex, mergeWith);
        int mergeEnd = std::max(minIndex, mergeWith);
        m_sharedIntervalBorders.erase(m_sharedIntervalBorders.begin() + mergeEnd);
        double mergedCount = m_borderCounts[mergeStart] + m_borderCounts[mergeEnd];
        m_borderCounts.erase(m_borderCounts.begin() + mergeEnd);
        m_borderCounts.erase(m_borderCounts.begin() + mergeStart);
        m_borderCounts.insert(m_borderCounts.begin() + mergeStart, mergedCount);
        m_numIntervals--;
    }

    int maxIndex = std::max_element(m_borderCounts.begin(), m_borderCounts.end()) - m_borderCounts.begin();
    double left = m_sharedIntervalBorders[maxIndex];
    double right = m_sharedIntervalBorders[maxIndex + 1];
    double mid = (left + right) / 2.0;
    m_sharedIntervalBorders.insert(m_sharedIntervalBorders.begin() + maxIndex + 1, mid);
    double splitCount = m_borderCounts[maxIndex] / 2.0;
    m_borderCounts[maxIndex] = splitCount;
    m_borderCounts.insert(m_borderCounts.begin() + maxIndex + 1, splitCount);
    m_numIntervals++;

}

int DynamicIntervalRRPIFOScheduler::GetFlowLabel(Ptr<QueueDiscItem> item) {
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

double DynamicIntervalRRPIFOScheduler::RankCal(Pkt pkt) {
    return pkt.flow_size;
}

void DynamicIntervalRRPIFOScheduler::Drop(Ptr<QueueDiscItem> item) {
    QueueDisc::Drop(item);
}

bool DynamicIntervalRRPIFOScheduler::DoEnqueue(Ptr<QueueDiscItem> item) {
    Ptr<Packet> packet = GetPointer(item->GetPacket());
    TenantTag my_tag;
    packet->PeekPacketTag(my_tag);
    int packet_size = packet->GetSize();
    int flow_size = my_tag.GetTenantId();
    if (flow_size == 100000001) {
        flow_size = 1;

        int queue_index = m_ackInputPointer % NUM_PIFOS;
        m_pifoCurrentSizes[queue_index] += packet_size;
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
    double rank = RankCal(Pkt(item, flow_id, packet_size, flow_size));

    PifoItem element = {rank, sendTime,Pkt(item, flow_id, packet_size, flow_size)};

    int interval_index = GetIntervalIndex(rank);
    int lb_id = m_loadBalancerIndex;
    m_loadBalancerIndex = (m_loadBalancerIndex + 1) % NUM_LOAD_BALANCERS;
    int best_pifo = SelectBestPifo(lb_id, interval_index);

    if (m_fifoBufferUsage[best_pifo] + packet_size < m_perFifoBufferLimit) {
        m_fifos[best_pifo].push_back(element);
        m_intervalCounters[lb_id][best_pifo][interval_index]++;
        m_fifoBufferUsage[best_pifo] += packet_size;

    } else {

        Drop(item);
        return false;
    }

    m_adjustCounter++;
    if (m_adjustCounter % ADJUST_PERIOD == 0) {
        AdjustIntervals();
    }
    return true;
}

Ptr<QueueDiscItem> DynamicIntervalRRPIFOScheduler::DoDequeue() {

    if (!m_ackFifo.empty()) {
        Ptr<QueueDiscItem> ack_item = m_ackFifo.front();
        m_ackFifo.pop_front();

        int packet_size = ack_item->GetPacket()->GetSize();
        int queue_index = m_ackOutputPointer % NUM_PIFOS;
        m_pifoCurrentSizes[queue_index] -= packet_size;
        m_ackOutputPointer++;

        return ack_item;

    }

    for (int i = 0; i < NUM_PIFOS; ++i) {
        int pifo_id = m_pifoIndex;
        m_pifoIndex = (m_pifoIndex + 1) % NUM_PIFOS;

        if (!m_pifos[pifo_id].empty()) {
            PifoItem element = *m_pifos[pifo_id].begin();
            m_pifos[pifo_id].erase(m_pifos[pifo_id].begin());
            m_pifoCurrentSizes[pifo_id] -= element.pkt.length;
            RefillFromFifo(pifo_id);

            return element.pkt.pktid;
        } else if (!m_fifos[pifo_id].empty()) {
            RefillFromFifo(pifo_id);
            if (!m_pifos[pifo_id].empty()) {
                PifoItem element = *m_pifos[pifo_id].begin();
                m_pifos[pifo_id].erase(m_pifos[pifo_id].begin());
                m_pifoCurrentSizes[pifo_id] -= element.pkt.length;

                return element.pkt.pktid;
            }
        }
    }
    return nullptr;
}

Ptr<const QueueDiscItem> DynamicIntervalRRPIFOScheduler::DoPeek(void) const {
    return nullptr;
}

bool DynamicIntervalRRPIFOScheduler::CheckConfig(void) {
    return true;
}

}
