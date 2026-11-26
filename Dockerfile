FROM swift:6.2-noble AS toolchain
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    qt6-base-dev pkg-config fonts-dejavu-core && rm -rf /var/lib/apt/lists/*
WORKDIR /src
ENV QT_QPA_PLATFORM=offscreen

FROM toolchain AS examples
COPY Package.swift Package.resolved ./
RUN swift package resolve --force-resolved-versions
COPY . .
RUN swift build && swift test && sh Scripts/test-event-loop.sh
CMD [".build/debug/Conversation"]
