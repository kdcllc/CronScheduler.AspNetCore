# BUILD IMAGE: docker build . -f "src\\CronSchedulerApp\Dockerfile" -t "cronschedulewebapp:latest"
# RUNNING THE IMAGE docker run --rm -it -p 5000:80 cronschedulewebapp:latest

FROM microsoft/dotnet:2.1-aspnetcore-runtime AS base
WORKDIR /app
EXPOSE 57989
EXPOSE 44369

FROM microsoft/dotnet:2.1-sdk AS build
WORKDIR /src
COPY src/CronSchedulerApp/CronSchedulerApp.csproj src/CronSchedulerApp/
RUN dotnet restore src/CronSchedulerApp/CronSchedulerApp.csproj
COPY . .
WORKDIR /src/src/CronSchedulerApp
RUN dotnet build CronSchedulerApp.csproj -c Release -o /app

FROM build AS publish
RUN dotnet publish CronSchedulerApp.csproj -c Release -o /app

FROM base AS final
WORKDIR /app
COPY --from=publish /app .
ENTRYPOINT ["dotnet", "CronSchedulerApp.dll"]
