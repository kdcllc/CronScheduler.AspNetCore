
# Build image
FROM kdcllc/dotnet-sdk:3.1-buster as builder
WORKDIR ./src/CronSchedulerApp
RUN dotnet publish --no-build -c Release -o /app

# App image
FROM mcr.microsoft.com/dotnet/core/aspnet:3.1 AS final
WORKDIR /app
COPY --from=builder /app .
ENTRYPOINT ["dotnet", "CronSchedulerApp.dll"]

