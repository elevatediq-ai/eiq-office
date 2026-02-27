# EPIC 1.1: Live Transcription Pipeline

## System: Meeting Intelligence Engine
## Epic Owner: VP of AI/ML
## Priority: P0 - Core feature
## Timeline: Q1 (8 weeks)

---

## Business Requirements

### Problem Statement
- Current: Teams rely on third-party services (Otter.ai, Fireflies.io) for meeting transcription
- Gap: No native transcription in OfficeIQ; data leaves infrastructure
- Opportunity: Sovereign, on-prem transcription unlocks enterprise sales

### Success Criteria
- **Accuracy:** 95% WER (word error rate) vs Whisper benchmark
- **Latency:** <800ms from speech input to UI display
- **Scale:** 250+ concurrent meetings, 99.9% uptime  
- **Cost:** <$0.10 per meeting hour vs $1.50 Otter
- **User Adoption:** 80% of recorded meetings use live transcription

### OKRs
- O: Become category leader in sovereign meeting intelligence
  - KR1: 100+ enterprise customers using live transcription
  - KR2: <500ms end-to-end latency (top 5% in industry)
  - KR3: Zero security incidents in transcription pipeline

---

## Technical Specifications

### Architecture Overview
```
NC Talk WebRTC Stream
    ↓
[Capture Service - WebSocket]
    ↓
[Audio Queue - Redis/RabbitMQ]
    ↓
[Whisper Workers - K8s GPU Pods (scaling 1-20)]
    ↓
[Diarization Service - pyannote (CPU)]
    ↓
[Word Timestamp Aggregation]
    ↓
[Live Transcript Stream - SSE/WebSocket to Portal UI]
```

### Component Definitions

#### 1.1.1: Whisper GPU Worker Service
**Description:** Kubernetes pod running Whisper Large-V3 model for transcription  
**Tech Stack:** Python, PyTorch, CUDA, Kubernetes  
**Acceptance Criteria:**
- Model loads in <30s on GPU pod startup
- Processes audio chunks (10-30s) in real-time (<5s turnaround)
- Handles 5 concurrent transcription jobs per pod
- Implements health check + graceful shutdown
- Metrics: latency, accuracy, GPU memory usage exported to Prometheus

**Definition of Done:**
- [ ] Docker image built & pushed to ECR
- [ ] Load test: 20 pods processing 100 concurrent meetings
- [ ] Model quantization tested (reduced memory footprint)
- [ ] Fallback to OpenAI Whisper API when GPU queue >2min

**Estimated Effort:** 8 story points  
**Dependencies:** GPU infrastructure, PyTorch setup

---

#### 1.1.2: WebSocket Audio Stream from NC Talk
**Description:** Tap into NC Talk's WebRTC MediaStream and forward raw audio to transcription pipeline  
**Tech Stack:** JavaScript, WebRTC API, Node.js  
**Acceptance Criteria:**
- Recording button in NC Talk triggers capture (zero UX disruption)
- Audio streamed as Opus-encoded frames (48kHz, stereo)
- Word-level timestamps captured from Whisper output
- Supports both browser mic and network audio
- Latency: <100ms from speaker mouth to transcription queue

**Definition of Done:**
- [ ] NC Talk iframe bridge implemented
- [ ] Audio streaming test with 10+ participants
- [ ] Timestamp sync verified across all participants
- [ ] Mobile PWA compatibility tested

**Estimated Effort:** 5 story points  
**Dependencies:** NC Talk API documentation

---

#### 1.1.3: Audio Queue Management
**Description:** Buffering & job distribution for audio processing  
**Tech Stack:** Redis/RabbitMQ, Node.js, BullMQ  
**Acceptance Criteria:**
- Queue survives service restarts (persistent)
- Automatic retry + exponential backoff (3 attempts max)
- Priority queue (P1 incidents > P2 project standups)
- Queue depth dashboard (for capacity planning)
- Alert if queue depth >1000 jobs

**Definition of Done:**
- [ ] Redis persistence backup tested
- [ ] Failover: alternate pod processes queue on node death
- [ ] Load test: 10K jobs queued & processed
- [ ] Dead letter queue for failed jobs

**Estimated Effort:** 3 story points  
**Dependencies:** Message queue infrastructure

---

#### 1.1.4: Multi-Language Auto-Detection
**Description:** Detect meeting language and switch transcription model dynamically  
**Tech Stack:** langdetect/fasttext, Python  
**Acceptance Criteria:**
- 100+ languages supported
- Language switch within first 10 seconds of meeting
- Code-switching detection (e.g., "Hello, comment ça va?")
- Accuracy >98% on language detection
- UI shows detected language (user can override)

**Definition of Done:**
- [ ] Test on 50+ multilingual meeting recordings
- [ ] Language switching latency <2s
- [ ] Dashboard showing language distribution across org

**Estimated Effort:** 3 story points  
**Dependencies:** langdetect library integration

---

#### 1.1.5: Fallback to OpenAI Whisper API
**Description:** When on-prem GPU is busy, route to cloud API (cost-optimized)  
**Tech Stack:** Python, OpenAI API client, cost tracking  
**Acceptance Criteria:**
- Fallback triggered when local queue >2min latency
- API calls batched to minimize cost
- Cost tracked per meeting (internal billing)
- User never sees latency degradation
- Max cloud spend: $50/month initially

**Definition of Done:**
- [ ] OpenAI API integration tested
- [ ] Cost dashboard implemented
- [ ] Fallback logic tested under load

**Estimated Effort:** 2 story points  
**Dependencies:** OpenAI API account, budget approval

---

#### 1.1.6: Speaker Diarization (Who Spoke When)
**Description:** Identify and label individual speakers in meeting  
**Tech Stack:** Python, pyannote/speaker-diarization-3.1, NumPy  
**Acceptance Criteria:**
- Diarization accuracy >90% on company meetings
- Fine-tuning on company voice profiles (speaker enrollment)
- Real-time diarization (not batch only)
- Handles 2-100 participants
- Output: speaker labels + confidence scores

**Definition of Done:**
- [ ] Collect 100 hour voice prints of team members (enrollment)
- [ ] Test on 50+ real company meetings
- [ ] Compare: generic model vs fine-tuned model performance
- [ ] UI shows speaker identification (click on speaker to verify)

**Estimated Effort:** 5 story points  
**Dependencies:** Voice enrollment infrastructure

---

#### 1.1.7: Real-Time Transcript Aggregation
**Description:** Merge word-level transcription + speaker labels into coherent stream  
**Tech Stack:** TypeScript, Node.js, Redis  
**Acceptance Criteria:**
- Aggregate 1000+ words/min from Whisper output
- Merge diarization labels (<100ms after received)
- Output: speaker + text + timestamp + confidence
- Deduplication: handle out-of-order word arrivals
- Streaming format: JSONL over WebSocket

**Definition of Done:**
- [ ] Benchmark: latency of full pipeline <800ms
- [ ] Test edge cases: overlapping speakers, silence, noise
- [ ] Load test: 100 concurrent aggregation streams

**Estimated Effort:** 4 story points  
**Dependencies:** Whisper + diarization services

---

#### 1.1.8: Live Transcript UI Streaming
**Description:** Display real-time transcript in portal as meeting runs  
**Tech Stack:** React, TypeScript, WebSocket, Tailwind CSS  
**Acceptance Criteria:**
- Words appear on screen <800ms after spoken
- Speaker name & avatar shown for each segment
- Scrolling smooth even with 100+ updates/sec
- Transcript searchable (Ctrl+F works)
- Copy-paste functionality works
- Mobile responsive

**Definition of Done:**
- [ ] Performance test: 1000 words/min rendering at 60fps
- [ ] Accessibility audit (WCAG 2.1 AA)
- [ ] Mobile testing (iOS Safari, Android Chrome)
- [ ] Screenshot testing for visual regression

**Estimated Effort:** 5 story points  
**Dependencies:** WebSocket protocol, React optimization

---

### Engineering Tasks

#### Backend Infrastructure
1. **GPU Node Provisioning** (2 pts)
   - Set up NVIDIA GPU nodes in K8s cluster
   - CUDA 12.1, cuDNN compatibility
   - Cost: $5-10/month per GPU node

2. **Prometheus Metrics** (2 pts)
   - Transcription latency histogram
   - GPU utilization gauge
   - Queue depth metrics

3. **Whisper Model Caching** (2 pts)
   - Download & cache model on GPU pod startup
   - Model versioning (support major.minor updates)
   - Rollback strategy if new model performs poorly

#### Frontend Implementation
1. **Record Button UX** (3 pts)
   - Permissions dialog (microphone access)
   - Visual indicator: recording ON/OFF
   - Stop + finalize meeting flow

2. **Transcript UI Components** (5 pts)
   - Speaker avatar circles
   - Segment highlighting
   - Timestamp scrubbing (click on timestamp to jump)
   - Export as PDF/docx

#### QA & Testing
1. **Accuracy Testing** (6 pts)
   - 50 meeting recordings with manual transcription
   - Compare WER across accents, noise levels, languages
   - Document accuracy by use case

2. **Stress Testing** (4 pts)
   - 250 concurrent meetings for 8 hours
   - Measure: latency, CPU/GPU/memory, error rates
   - Document: max concurrent limit

3. **Security Testing** (3 pts)
   - Penetration test: audio injection attack
   - Verify: audio data not leaving cluster
   - Audit: who has access to audio files

---

## Rollout Plan

### Phase 1: Internal Alpha (Week 1-2)
- Deploy on test cluster
- OfficeIQ team eats own dog food
- Collect feedback on UX

### Phase 2: Beta (Week 3-4)
- 50 pilot customers (free, under NDA)
- Real-world accuracy testing
- Feedback incorporation

### Phase 3: General Availability (Week 5-8)
- Full rollout to all customers
- Documentation & training videos
- Pricing plans (included at no cost vs SKU)

---

## Success Dashboard

**Metrics to Track:**
- Transcription accuracy (target: 95% WER)
- End-to-end latency (target: <800ms p95)
- GPU utilization (target: 70-85%)
- Cost per meeting hour (target: <$0.05)
- User adoption (% of meetings recorded with transcription)
- Customer NPS on transcription feature

**Telemetry:**
- Track every transcription job (latency, model, cost, accuracy)
- Track user interactions (search, export, copy)
- Error tracking (failures, retries, fallbacks)

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| GPU node costs exceed budget | Medium | High | Implement cost controls, investigate cheaper hardware |
| Transcription accuracy disappoints customers | Medium | High | Extensive testing before GA, clear accuracy expectations |
| Privacy concerns on audio storage | Low | Critical | Encrypt at rest, implement retention policies, audit logs |
| Scaling to 1000+ concurrent meetings | Medium | Medium | Load test early, design for horizontal scaling |

---

## Dependencies

**External:**
- NVIDIA GPU availability (supply chain risk)
- PyTorch/CUDA compatibility updates
- OpenAI Whisper API pricing

**Internal:**
- NC Talk WebRTC stream access (coordinate with Talk team)
- K8s cluster capacity for GPU nodes
- Data storage for audio files (S3 budget)

---

## Resources Allocated

- **Lead Engineer:** 1 FTE (backend, ML infrastructure)
- **Frontend Engineer:** 1 FTE (UI, WebSocket)
- **ML Engineer:** 0.5 FTE (diarization, fine-tuning)
- **QA Engineer:** 1 FTE (accuracy testing, performance)
- **DevOps:** 0.5 FTE (GPU infrastructure, monitoring)

**Total:** 4 FTE for 8 weeks

---

## Q&A & Decision Points

**Q: Should we charge for live transcription?**  
A: No—include free with all plans for competitive advantage. Upsell: advanced editing, RCA generation.

**Q: What if GPU costs explode?**  
A: Implement hard caps per customer, prioritize by subscription tier, consider on-demand scaling.

**Q: How do we handle non-English meetings?**  
A: Multi-language models supported. Fine-tune for company languages. Roadmap: real-time translation.

---

*Last Updated: Feb 27, 2026*  
*JIRA Ticket: IQ-1.1.1 through IQ-1.1.8*
