FROM mcr.microsoft.com/dotnet/core/runtime:3.0 AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/core/sdk:3.0 AS build
WORKDIR /src
COPY ["src/CronSchedulerWorker/CronSchedulerWorker.csproj", "src/CronSchedulerWorker/"]
RUN dotnet restore "src/CronSchedulerWorker/CronSchedulerWorker.csproj"

COPY . .

RUN dotnet build "src/CronSchedulerWorker/CronSchedulerWorker.csproj" -c Release -o /app
RUN dotnet publish "src/CronSchedulerWorker/CronSchedulerWorker.csproj" -c Release -o /app

FROM base AS final
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "CronSchedulerWorker.dll"]
