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

ENTRYPOINT ["dotnet", "run"]
