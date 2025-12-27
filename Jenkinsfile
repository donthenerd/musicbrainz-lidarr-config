pipeline {
    agent any

    environment {
        DEPLOY_HOST = 'drteeth'
        DEPLOY_PATH = '/opt/docker/musicbrainz-docker'
        // Credentials from Jenkins credential store
        POSTGRES_USER = credentials('musicbrainz-postgres-user')
        POSTGRES_PASSWORD = credentials('musicbrainz-postgres-password')
        POSTGRES_HOST = '10.21.1.9'
        NFS_HOST = '10.21.1.9'
        SPOTIFY_CLIENT_ID = credentials('musicbrainz-spotify-id')
        SPOTIFY_CLIENT_SECRET = credentials('musicbrainz-spotify-secret')
        SPOTIFY_REDIRECT_URL = 'https://musicbrainz.digmyjam.com'
        FANART_KEY = credentials('musicbrainz-fanart-key')
        LASTFM_KEY = credentials('musicbrainz-lastfm-key')
        LASTFM_SECRET = credentials('musicbrainz-lastfm-secret')
        TADB_KEY = '2'
        TRAEFIK_DOMAIN = 'musicbrainz.digmyjam.com'
        MUSICBRAINZ_IP = '10.21.1.10'
        POSTGRES_SHARED_BUFFERS = '4GB'
        SOLR_HEAP = '16g'
        SOLR_UID = '8675309'
        SOLR_GID = '8675309'
        NFS_SOLRDATA_PATH = '/mnt/eightsixes1/borrowed/sabnzbd/musicbrainz-solrdata'
        NFS_SOLRDUMP_PATH = '/mnt/eightsixes1/borrowed/sabnzbd/musicbrainz-solr-backup'
    }

    stages {
        stage('Validate') {
            steps {
                echo 'Validating configuration files...'
                sh '''
                    # Check YAML syntax
                    for file in compose/*.yml; do
                        python3 -c "import yaml; yaml.safe_load(open('$file'))" || exit 1
                        echo "  ✓ $file"
                    done
                '''
            }
        }

        stage('Build Config') {
            steps {
                echo 'Substituting environment variables...'
                sh '''
                    mkdir -p build/compose build/scripts
                    for file in compose/*.yml; do
                        envsubst < "$file" > "build/$(basename $file)"
                    done
                    cp scripts/*.sh build/scripts/
                    chmod +x build/scripts/*.sh
                '''
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                echo "Deploying to ${DEPLOY_HOST}..."
                sshagent(['drteeth-ssh-key']) {
                    sh '''
                        # Create remote directories
                        ssh ${DEPLOY_HOST} "mkdir -p ${DEPLOY_PATH}/local/compose ${DEPLOY_PATH}/scripts"

                        # Copy compose files
                        scp build/*.yml ${DEPLOY_HOST}:${DEPLOY_PATH}/local/compose/

                        # Copy scripts
                        scp build/scripts/*.sh ${DEPLOY_HOST}:${DEPLOY_PATH}/scripts/
                        ssh ${DEPLOY_HOST} "chmod +x ${DEPLOY_PATH}/scripts/*.sh"
                    '''
                }
            }
        }

        stage('Restart Services') {
            when {
                branch 'main'
            }
            steps {
                echo 'Restarting Docker services...'
                sshagent(['drteeth-ssh-key']) {
                    sh '''
                        ssh ${DEPLOY_HOST} "cd ${DEPLOY_PATH} && docker compose up -d"
                    '''
                }
            }
        }

        stage('Health Check') {
            when {
                branch 'main'
            }
            steps {
                echo 'Running health check...'
                sshagent(['drteeth-ssh-key']) {
                    sh '''
                        # Wait for services to start
                        sleep 30
                        ssh ${DEPLOY_HOST} "${DEPLOY_PATH}/scripts/health-check.sh"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Deployment successful!'
        }
        failure {
            echo 'Deployment failed!'
            // Add notification (Slack, email, etc.)
        }
        always {
            cleanWs()
        }
    }
}
