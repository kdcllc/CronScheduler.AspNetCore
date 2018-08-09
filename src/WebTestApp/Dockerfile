FROM microsoft/dotnet:2.1.2-aspnetcore-runtime AS base
WORKDIR /app
EXPOSE 57989
EXPOSE 44369

FROM microsoft/dotnet:2.1-sdk AS build
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
