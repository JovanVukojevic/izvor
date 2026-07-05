FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY Izvor.Api/Izvor.Api.csproj Izvor.Api/
RUN dotnet restore Izvor.Api/Izvor.Api.csproj

COPY Izvor.Api/ Izvor.Api/
RUN dotnet publish Izvor.Api/Izvor.Api.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

USER app
ENTRYPOINT ["dotnet", "Izvor.Api.dll"]
