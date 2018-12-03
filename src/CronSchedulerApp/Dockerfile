# BUILD IMAGE: docker build . -f "src\\WebTestApp\Dockerfile" -t "cronschedulewebapp:latest"
# RUNNING THE IMAGE docker run --rm -it -p 5000:80 cronschedulewebapp:latest

FROM microsoft/dotnet:2.1.5-aspnetcore-runtime AS base
WORKDIR /app
EXPOSE 57989
EXPOSE 44369

FROM microsoft/dotnet:2.1.403-sdk AS build
WORKDIR /src
COPY src/WebTestApp/WebTestApp.csproj src/WebTestApp/
RUN dotnet restore src/WebTestApp/WebTestApp.csproj
COPY . .
WORKDIR /src/src/WebTestApp
RUN dotnet build WebTestApp.csproj -c Release -o /app

FROM build AS publish
RUN dotnet publish WebTestApp.csproj -c Release -o /app

FROM base AS final
WORKDIR /app
COPY --from=publish /app .
ENTRYPOINT ["dotnet", "WebTestApp.dll"]
