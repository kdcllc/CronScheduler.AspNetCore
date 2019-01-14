ARG sdkImage=kdcllc/dotnet
ARG sdkTag=2.1-sdk
ARG runtimeImage=microsoft/dotnet
ARG runtimeTag=2.1-aspnetcore-runtime
ARG coreversion=netcore21

# Build image
FROM ${sdkImage}:${sdkTag} as builder
RUN dotnet publish "./src/CronSchedulerApp/CronSchedulerApp.csproj" -c Release -p:NetCoreVersion=${coreversion} -o /app
#RUN npm -v

# App image
FROM ${runtimeImage}:${runtimeTag} AS final
WORKDIR /app
COPY --from=builder /app .
ENTRYPOINT ["dotnet", "CronSchedulerApp.dll"]

