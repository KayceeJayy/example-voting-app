# Build stage: .NET 10 LTS
FROM mcr.microsoft.com/dotnet/sdk@sha256:fe0fd4e93bd2fbb47c883b7a6369e5c8d3db8bf01cdc5981f6ee35fbdf3ff4fb AS build

WORKDIR /source

COPY *.csproj ./
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /out --no-restore

# Production stage
FROM mcr.microsoft.com/dotnet/runtime@sha256:80a51954ac70925e5783cb1ed35129a4243dcb1cddef20066b67346e17db284d AS final

ENV HOME=/tmp \
    DOTNET_CLI_HOME=/tmp \
    DOTNET_EnableDiagnostics=0

WORKDIR /app

COPY --from=build --chown=10001:10001 /out/ ./

# Non-root execution
USER 10001:10001

ENTRYPOINT ["dotnet", "Worker.dll"]
