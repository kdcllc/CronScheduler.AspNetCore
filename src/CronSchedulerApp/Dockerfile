ARG sdkImage
ARG sdkTag
ARG runtimeImage
ARG runtimeTag

ARG RUNTESTS="false"
ARG VERBOSE="false"

# Build image
FROM ${sdkImage}:${sdkTag} as builder
WORKDIR ./src/CronSchedulerApp
RUN dotnet publish --no-build -c Release  -o /app

#WORKDIR ./src/CronSchedulerApp
#RUN dotnet build --no-restore -c Release -v d
#RUN dotnet publish --no-build -c Release -o /app

# App image
FROM ${runtimeImage}:${runtimeTag} AS final
WORKDIR /app
COPY --from=builder /app .
ENTRYPOINT ["dotnet", "CronSchedulerApp.dll"]

