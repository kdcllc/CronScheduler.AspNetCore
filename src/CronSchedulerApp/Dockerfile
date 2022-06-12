#See https://aka.ms/containerfastmode to understand how Visual Studio uses this Dockerfile to build your images for faster debugging.
# docker build --pull --rm -f "src\CronSchedulerApp\Dockerfile" -t cronscheduler:latest .
# docker run --rm -d  -p 4443:443/tcp -p 8080:80/tcp cronscheduler:latest

FROM mcr.microsoft.com/dotnet/aspnet:6.0 AS base
WORKDIR /app
EXPOSE 80
EXPOSE 443

FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build
WORKDIR /src

COPY ["build/", "build/"]

COPY ["Directory.Build.props", "Directory.Build.props"]
COPY ["Directory.Build.targets", "Directory.Build.targets"]

COPY ["src/CronSchedulerApp/CronSchedulerApp.csproj", "src/CronSchedulerApp/"]
COPY ["src/CronScheduler.AspNetCore/CronScheduler.AspNetCore.csproj", "src/CronScheduler.AspNetCore/"]
COPY ["src/CronScheduler.Extensions/CronScheduler.Extensions.csproj", "src/CronScheduler.Extensions/"]
RUN dotnet restore "src/CronSchedulerApp/CronSchedulerApp.csproj"
COPY . .
WORKDIR "/src/src/CronSchedulerApp"
RUN dotnet build "CronSchedulerApp.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "CronSchedulerApp.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "CronSchedulerApp.dll"]
