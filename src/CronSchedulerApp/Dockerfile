
# Build image
FROM kdcllc/dotnet:3.0-sdk-buster as builder
WORKDIR ./src/CronSchedulerApp
RUN dotnet publish --no-build -c Release -o /app

# App image
FROM mcr.microsoft.com/dotnet/core/aspnet:3.0.0-preview8-buster-slim AS final
WORKDIR /app
COPY --from=builder /app .
ENTRYPOINT ["dotnet", "CronSchedulerApp.dll"]

