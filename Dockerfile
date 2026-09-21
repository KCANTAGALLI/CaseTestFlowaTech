# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/StatusApi/StatusApi.csproj src/StatusApi/
RUN dotnet restore src/StatusApi/StatusApi.csproj

COPY src/StatusApi/ src/StatusApi/
WORKDIR /src/src/StatusApi
RUN dotnet publish -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

RUN adduser --disabled-password --gecos "" appuser \
    && chown -R appuser:appuser /app
USER appuser

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:5000
ENV ASPNETCORE_ENVIRONMENT=Production

EXPOSE 5000

ENTRYPOINT ["dotnet", "StatusApi.dll"]
