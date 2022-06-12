#See https://aka.ms/containerfastmode to understand how Visual Studio uses this Dockerfile to build your images for faster debugging.

FROM mcr.microsoft.com/dotnet/runtime:6.0 AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build
WORKDIR /src

COPY ["build/", "build/"]

COPY ["Directory.Build.props", "Directory.Build.props"]
COPY ["Directory.Build.targets", "Directory.Build.targets"]

COPY ["src/CronSchedulerWorker/CronSchedulerWorker.csproj", "src/CronSchedulerWorker/"]
COPY ["src/CronScheduler.Extensions/CronScheduler.Extensions.csproj", "src/CronScheduler.Extensions/"]
RUN dotnet restore "src/CronSchedulerWorker/CronSchedulerWorker.csproj"
COPY . .
WORKDIR "/src/src/CronSchedulerWorker"
RUN dotnet build "CronSchedulerWorker.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "CronSchedulerWorker.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "CronSchedulerWorker.dll"]
