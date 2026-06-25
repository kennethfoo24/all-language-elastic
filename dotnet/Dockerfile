FROM mcr.microsoft.com/dotnet/sdk:9.0
WORKDIR /App

# Copy everything
COPY dotnet/ ./

# Restore as distinct layers
RUN dotnet restore
RUN dotnet dev-certs https --clean
RUN dotnet dev-certs https

# Build and publish a release
RUN dotnet publish -c Release -o out

# Build runtime image
EXPOSE 5555

# Run the PUBLISHED app, not `dotnet run`.
# `dotnet run` triggers an MSBuild restore/build at container start; under EDOT
# .NET auto-instrumentation the injected CLR profiler (CORECLR_ENABLE_PROFILING)
# attaches to those build processes and the startup hangs before Kestrel binds.
# It also pulls in launchSettings.json (localhost:5168) instead of appsettings.json
# (0.0.0.0:5555). Running the published DLL avoids both.
ENTRYPOINT ["dotnet", "out/dotnet-app.dll"]
