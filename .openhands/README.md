# OpenHands Agent Configuration

This directory contains configuration files for OpenHands agents to complete the Family Network Platform project.

## Files Overview

### `project-config.yaml`
Defines the overall project configuration including:
- Project metadata and success criteria
- Agent skill requirements
- Quality gates and communication preferences
- Execution strategy preferences

### `task-definitions.yaml`
Comprehensive task breakdown including:
- 4 execution phases with 15 total tasks
- Task dependencies and priorities
- Estimated hours and success criteria
- Files to create for each task
- Quality checkpoints and execution rules

### `agent-prompts.md`
Specialized prompts for different types of work:
- Technical documentation prompts
- Family documentation prompts
- Script development prompts
- Configuration and testing prompts
- Quality standards and conventions

### `execution-strategy.md`
Detailed execution strategy including:
- Phase-by-phase execution order
- Task delegation strategies (single vs multi-agent)
- Quality assurance procedures
- Risk mitigation approaches
- Success metrics and completion criteria

## Quick Start for Agents

### 1. Understand the Project
- Read `../PROJECT_COMPLETION_PLAN.md` for full context
- Review `project-config.yaml` for project overview
- Understand the goal: Complete family network platform with universal device support

### 2. Choose Execution Approach
- **Single Agent** (recommended): Complete all tasks sequentially for consistency
- **Multi-Agent**: Specialize by domain for faster completion

### 3. Follow Task Order
1. **Phase 1**: Technical Infrastructure (20 hours)
2. **Phase 2**: Family Experience (18 hours)
3. **Phase 3**: Operations & Maintenance (16 hours)
4. **Phase 4**: Service Expansion (26 hours)

### 4. Use Appropriate Prompts
- Reference `agent-prompts.md` for task-specific guidance
- Follow quality standards and conventions
- Maintain focus on family user experience

### 5. Validate Continuously
- Check success criteria after each task
- Run integration tests after each phase
- Ensure family members can complete setup in <10 minutes

## Key Principles

1. **Universal Compatibility**: No platform-specific solutions
2. **Family-First**: Non-technical users are the priority
3. **Production Quality**: Enterprise-grade reliability and security
4. **Infinite Scalability**: Add services without client changes
5. **Zero Complexity**: Family members never manage VPN connections

## Success Criteria

The project is complete when:
- ✅ All core services deploy with one command
- ✅ Family setup takes <10 minutes on any device
- ✅ Comprehensive documentation for all user types
- ✅ Production-grade monitoring and security
- ✅ Zero ongoing technical maintenance for family members

## Getting Help

- Review existing documentation in `docs/` directory
- Check `PROJECT_COMPLETION_PLAN.md` for detailed context
- Follow patterns established in existing code and documentation
- Prioritize family user experience in all decisions

Start with Phase 1 tasks and work systematically through each phase. The project is well-scaffolded and ready for completion!